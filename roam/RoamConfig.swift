//
//  RoamConfig.swift
//  roam
//
//  Central configuration for roam's backend. All API traffic (Claude, ElevenLabs,
//  AssemblyAI, part lookup) routes through a single Cloudflare Worker (see the
//  /worker directory) so API keys never ship inside the app binary.
//
//  Set `workerBaseURL` below to your deployed worker, e.g.
//      https://roam-proxy.<your-subdomain>.workers.dev
//  or, for local development, run `npm run dev` (wrangler) in /worker and point
//  the app at http://127.0.0.1:8787 — either by editing the fallback below or by
//  launching with the ROAM_WORKER_URL environment variable set.
//

import Foundation

enum RoamConfig {
    /// Base URL of the roam proxy worker (no trailing slash).
    /// Overridable at runtime via the ROAM_WORKER_URL environment variable so you
    /// can switch between local `wrangler dev` and a deployed worker without a rebuild.
    static let workerBaseURL: String = {
        if let env = ProcessInfo.processInfo.environment["ROAM_WORKER_URL"], !env.isEmpty {
            return env.hasSuffix("/") ? String(env.dropLast()) : env
        }
        // TODO: replace with your deployed worker URL.
        return "https://your-worker-name.your-subdomain.workers.dev"
    }()

    static var chatURL: String { "\(workerBaseURL)/chat" }
    static var ttsURL: String { "\(workerBaseURL)/tts" }
    static var transcribeTokenURL: String { "\(workerBaseURL)/transcribe-token" }
    static var transcribeURL: String { "\(workerBaseURL)/transcribe" }
    static var partLookupURL: String { "\(workerBaseURL)/part-lookup" }

    /// Default Claude model used for vision + reasoning across the app.
    static let defaultModel = "claude-sonnet-4-6"
}
