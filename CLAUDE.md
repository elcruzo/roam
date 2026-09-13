# CLAUDE.md — working in the roam repo

roam is a standalone macOS menu-bar companion (Swift/SwiftUI) that helps read
hardware: highlight a screen region or push-to-talk, and it explains PCBs,
schematics, and components out loud. It's a de-branded fork of the open-source
Clicky app, repurposed for electronics. **Not affiliated with any product it looks at.**

## Layout
- `roam/` — the macOS app. Xcode 16 file-system-synchronized group, so **new
  `.swift` files in this folder are auto-added to the target** (no pbxproj edits).
- `worker/` — Cloudflare Worker. The ONLY place API keys live. Routes: `/chat`,
  `/tts`, `/transcribe-token`, `/part-lookup`, `/health`.

## Key files
- `RoamConfig.swift` — single source of truth for the backend URL (`ROAM_WORKER_URL`
  env var overrides) and default model. Change the worker URL here, nowhere else.
- `CompanionManager.swift` — `@MainActor` state machine. Holds the system prompts
  (voice, spatial region, dictation-agent), the response pipeline, the `[POINT]`
  parser, and both new controllers (spatial gesture + dictation).
- `SpatialGestureOverlay.swift` — records the cursor "circle" during a ⌃⌥ hold, draws
  the ink trail, returns the bounding region (hero feature).
- `DictationShortcutMonitor.swift` — Control+Command hold (listen-only CGEvent tap).
- `TextInjector.swift` — inserts text into the focused field (clipboard ⌘V + a
  CGEvent unicode path).
- `CompanionScreenCaptureUtility.swift` — `captureAllScreensAsJPEG()` (voice/dictation)
  and `captureRegion(globalRect:screen:)` (high-res crop for the circled region).

## Conventions
- Keys never touch the app; everything goes through the Worker.
- Interactions share one `CompanionManager`, one overlay, one conversation history.
- **Spatial context** = hold ⌃⌥, circle + talk → crop to the circle (or full screen if
  no movement). **Dictation** = hold ⌃⌘, say what to write → always screen-aware: reads
  the screen, generates the text, types it into the focused field (no wake word). Disjoint
  modifiers (⌃⌥ vs ⌃⌘, and off Fn) so nothing collides.
- Telemetry is a no-op shim (`RoamAnalytics`) — nothing is sent anywhere.

## Build / run
- App: open `roam.xcodeproj` in Xcode 16+, set a signing team, ⌘R. Needs
  Microphone + Screen Recording + Accessibility.
- Worker: `cd worker && npm i && npm run dev` (local) or `npm run deploy`.

## Extension points
- `/part-lookup` endpoint is live but not yet wired into an in-app action.
- Overlay pointing uses `[POINT:x,y:label]`. PCB-specific `[BOX]`/`[TRACE]`/`[PROBE]`
  primitives are the intended next layer on the overlay renderer.
