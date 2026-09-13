/**
 * roam Proxy Worker
 *
 * Proxies requests to Claude, ElevenLabs, and AssemblyAI so the macOS app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets and never leave
 * the edge. roam is a standalone project — this backend has no external
 * dependencies beyond the three upstream APIs.
 *
 * Routes (all POST unless noted):
 *   POST /chat             → Anthropic Messages API (streaming SSE passthrough)
 *   POST /tts              → ElevenLabs text-to-speech (audio/mpeg)
 *   POST /transcribe-token → AssemblyAI temporary streaming token (proxied GET)
 *   POST /part-lookup      → PCB part/component context, backed by Claude
 *   GET  /health           → liveness probe
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  OPENAI_API_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "roam-proxy" });
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      switch (url.pathname) {
        case "/chat":
          return await handleChat(request, env);
        case "/tts":
          return await handleTTS(request, env);
        case "/transcribe-token":
          return await handleTranscribeToken(env);
        case "/part-lookup":
          return await handlePartLookup(request, env);
        case "/transcribe":
          return await handleTranscribe(request, env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return json({ error: String(error) }, 500);
    }

    return new Response("Not found", { status: 404 });
  },
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeToken(env: Env): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe-token] AssemblyAI token error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

/**
 * OpenAI audio transcription proxy. The app POSTs a multipart/form-data body
 * (audio file + model/language/response_format fields) exactly as OpenAI's
 * /v1/audio/transcriptions expects; we just forward it and attach the key.
 * Keeps the OpenAI key server-side instead of baked into the app.
 */
async function handleTranscribe(request: Request, env: Env): Promise<Response> {
  const contentType = request.headers.get("content-type") || "multipart/form-data";
  const body = await request.arrayBuffer();

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": contentType,
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe] OpenAI API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: { "content-type": response.headers.get("content-type") || "application/json" },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

/**
 * PCB part / component context lookup.
 *
 * This is roam's own backend tool — the "duplicate the backend functionality we
 * want" seam. It takes a part number, silkscreen marking, or free-text query and
 * returns a compact, structured summary using Claude's knowledge. No third-party
 * distributor keys required. Swap the body for a real DigiKey/Mouser/Nexar call
 * later if you want live pricing/stock.
 *
 * Request:  { "query": "AMS1117-3.3", "context"?: "seen on a 3v3 rail near a sensor" }
 * Response: { "summary": "...", "raw": "...", "query": "..." }
 */
async function handlePartLookup(request: Request, env: Env): Promise<Response> {
  const { query, context } = (await request.json()) as {
    query?: string;
    context?: string;
  };

  if (!query || !query.trim()) {
    return json({ error: "missing 'query'" }, 400);
  }

  const system =
    "you are a concise electronics reference. given a part number, package marking, " +
    "or component description, identify the most likely part and summarize what an " +
    "engineer debugging a board needs: what it is, its function, key pins/pinout notes, " +
    "typical operating voltage/current, common failure modes, and what to probe. " +
    "if the marking is ambiguous, say so and list the top candidates. keep it tight — " +
    "no marketing, no filler. plain text, no markdown headers.";

  const userText = context
    ? `Part / marking: ${query}\nWhere it was seen: ${context}`
    : `Part / marking: ${query}`;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 512,
      system,
      messages: [{ role: "user", content: userText }],
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/part-lookup] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
  };
  const summary =
    data.content?.find((b) => b.type === "text")?.text?.trim() ?? "";

  return json({ query, summary, raw: summary });
}
