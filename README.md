# roam

**roam** is a floating macOS companion that lives next to your cursor and helps you
read hardware. Highlight any region of the screen — a KiCad/Trace PCB layout, a
schematic, a photo of a real board under a microscope, a datasheet — and roam
captures just that region, figures out what it is, and tells you out loud.
Or hold a push-to-talk key and ask it anything about what's on screen.

It's a Clicky-style buddy ([farzaa/clicky](https://github.com/farzaa/clicky), MIT),
rebuilt and repurposed for electronics debugging. **roam is an independent side
project — it is not affiliated with any product it can look at.**

## What it does

- **Spatial context — circle + talk (the hero move).** Hold **⌃⌥** (control +
  option), hover/circle your cursor around a part *while you ask about it* ("what
  does this trace connect to?"), and release. roam crops to exactly what you circled
  and answers out loud — component, net, sub-circuit, test point, likely part number,
  what to probe, and what looks off. Don't move the cursor and it just uses the whole
  screen. One fused gesture, no screenshot-annotate-paste.
- **Screen-aware dictation — write into any field.** Hold **Control+Command**, say what
  you want ("reply thanking them and ask their use case"), and roam reads the screen,
  writes it in your voice, and types it straight into whatever text field you're in.
  Always screen-aware — plain verbatim dictation is left to dedicated tools.
- **Hardware brain.** The spatial/voice path uses a PCB-savvy system prompt: reference
  designators, nets, power/ground, i2c/spi/uart buses, decoupling, and failure
  modes like near-shorts, thin traces, cold joints, and bad vias.

Everything is spoken (ElevenLabs), transcribed (AssemblyAI), and reasoned by Claude.

## Architecture

```
roam/
  roam/                 # macOS SwiftUI menu-bar app (the companion)
    SpatialGestureOverlay.swift    # circle-to-focus ink trail + path bounds (hero)
    DictationShortcutMonitor.swift # Control+Command hold for screen-aware dictation
    TextInjector.swift             # types generated/dictated text into the focused field
    CompanionScreenCaptureUtility.swift  # full-screen + high-res region capture
    CompanionManager.swift         # state machine, prompts, response pipeline
    ClaudeAPI.swift                # streaming vision client
    RoamConfig.swift               # single place for the backend URL + model
    ...
  worker/               # Cloudflare Worker — the only place API keys live
    src/index.ts        # /chat, /tts, /transcribe-token, /part-lookup, /health
```

Keys never ship in the app. The Swift app talks only to your Worker; the Worker
holds the Anthropic / ElevenLabs / AssemblyAI secrets and proxies upstream.

## Setup

### 1. Deploy the backend (or run it locally)

```bash
cd worker
npm install

# set your secrets (stored server-side on Cloudflare, never in the app)
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
# ELEVENLABS_VOICE_ID is a non-secret [vars] entry in wrangler.toml — edit to taste

npm run deploy          # production
# or, for local dev:
npm run dev             # wrangler dev on http://127.0.0.1:8787
```

Endpoints: `POST /chat` (Claude SSE passthrough), `POST /tts` (ElevenLabs mpeg),
`POST /transcribe-token` (AssemblyAI temp token), `POST /part-lookup`
(Claude-backed component context), `GET /health`.

### 2. Point the app at your Worker

Edit `roam/RoamConfig.swift` and set `workerBaseURL` to your deployed Worker, e.g.
`https://roam-proxy.<subdomain>.workers.dev`. For local dev, either put
`http://127.0.0.1:8787` there or launch the app with the env var
`ROAM_WORKER_URL=http://127.0.0.1:8787` (it overrides the fallback at runtime).

### 3. Build the app

Open `roam.xcodeproj` in Xcode 16+, pick your signing team (the bundled team ids
were cleared, so set your own under *Signing & Capabilities*), and run (**⌘R**).
Grant **Microphone**, **Screen Recording**, and **Accessibility** when prompted.

## Try it

- Hold **⌃⌥**, circle a component while saying *"what does this connect to?"*, release
  → roam crops to what you circled and answers out loud.
- In a Gmail reply, click the field, hold **Control+Command** and say *"reply thanking them
  and ask their use case"* → it reads the thread and types a reply in your voice.

## Extension points

- **`POST /part-lookup`** is live and testable today:
  ```bash
  curl -X POST $WORKER/part-lookup -d '{"query":"AMS1117-3.3","context":"near a 3v3 rail"}'
  ```
  Wiring it into an in-app "look up this part" action is a natural next step.
- **Richer overlay tags.** Pointing currently uses Clicky's `[POINT:x,y:label]`
  primitive (fully working). PCB-specific `[BOX]`, `[TRACE]`, and `[PROBE]`
  primitives — boxing a component, drawing a polyline along a net, marking a probe
  point — are the intended next layer on top of the overlay renderer.

## Credit

Built on the open-source Clicky app by [@farzaa](https://github.com/farzaa/clicky)
(MIT). roam keeps that license.
