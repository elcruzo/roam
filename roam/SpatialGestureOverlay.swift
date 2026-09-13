//
//  SpatialGestureOverlay.swift
//  roam
//
//  Clicky's "spatial context" gesture: while the push-to-talk key is held, the
//  user hovers/circles the cursor around the thing they're asking about. This
//  records the cursor path, draws a fading ink trail, and hands back the bounding
//  region on release so the app can crop to exactly what was circled.
//
//  It is intentionally passive — a click-through overlay that only *observes* the
//  real cursor (polling NSEvent.mouseLocation), so the user keeps interacting with
//  whatever is underneath while they circle and talk.
//

import AppKit

struct SpatialGestureResult {
    /// Padded bounding box of the circled path, in global AppKit coords (bottom-left origin).
    let globalRect: CGRect
    /// The screen the gesture happened on.
    let screen: NSScreen
}

@MainActor
final class SpatialGestureController {
    private var window: SpatialGestureWindow?
    private var pollTimer: Timer?
    private var points: [CGPoint] = []          // global AppKit coords
    private var startScreen: NSScreen?
    private(set) var isRecordingGesture = false

    /// How much padding to add around the circled path when cropping (points).
    private static let regionPadding: CGFloat = 28
    /// Minimum bbox area (points²) for the gesture to count as "a region".
    /// Below this we treat it as "no meaningful circle" → caller uses full screen.
    private static let minRegionArea: CGFloat = 60 * 60
    /// Minimum total pointer travel (points) before we consider it a deliberate circle.
    private static let minTravel: CGFloat = 40

    func begin() {
        guard !isRecordingGesture else { return }
        isRecordingGesture = true
        points.removeAll(keepingCapacity: true)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        startScreen = screen
        points.append(mouse)

        if let screen {
            let window = SpatialGestureWindow(screen: screen)
            self.window = window
            window.orderFrontRegardless()
        }

        // Poll the real cursor ~60 Hz and feed the trail.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard isRecordingGesture else { return }
        let mouse = NSEvent.mouseLocation
        if let last = points.last, hypot(mouse.x - last.x, mouse.y - last.y) < 1.5 { return }
        points.append(mouse)

        // Draw the trail in the start screen's local (window) coordinates.
        if let window = window, let screen = startScreen {
            let local = points.map { CGPoint(x: $0.x - screen.frame.origin.x,
                                             y: $0.y - screen.frame.origin.y) }
            window.trailView.update(points: local)
        }
    }

    /// Stops recording and returns the circled region, or nil if the gesture was
    /// too small/still to be a deliberate circle (caller should use full screen).
    func end() -> SpatialGestureResult? {
        guard isRecordingGesture else { return nil }
        isRecordingGesture = false

        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
        let window = self.window
        self.window = nil
        window?.trailView.update(points: [])

        guard let screen = startScreen, points.count >= 2 else { return nil }

        // Total travel — a near-motionless hold isn't a circle.
        var travel: CGFloat = 0
        for i in 1..<points.count {
            travel += hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y)
        }
        guard travel >= Self.minTravel else { return nil }

        // Bounding box of the path, padded, clamped to the screen.
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -Self.regionPadding, dy: -Self.regionPadding)
        rect = rect.intersection(screen.frame)

        guard rect.width * rect.height >= Self.minRegionArea else { return nil }
        return SpatialGestureResult(globalRect: rect, screen: screen)
    }
}

/// Borderless, click-through overlay that hosts the ink-trail view for one screen.
final class SpatialGestureWindow: NSWindow {
    let trailView: SpatialTrailView

    init(screen: NSScreen) {
        trailView = SpatialTrailView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true            // click-through: user keeps using apps underneath
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: true)
        setFrameOrigin(screen.frame.origin)
        contentView = trailView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the cursor path as a soft, fading accent-colored trail.
final class SpatialTrailView: NSView {
    private var points: [CGPoint] = []

    func update(points: [CGPoint]) {
        self.points = points
        needsDisplay = true
    }

    override var isFlipped: Bool { false } // AppKit bottom-left origin, matches our coords

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard points.count >= 2 else { return }

        let accent = NSColor(calibratedRed: 0.20, green: 0.68, blue: 1.0, alpha: 1.0)
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.lineWidth = 5
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }

        accent.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 12
        path.stroke()                       // soft outer glow
        accent.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 4
        path.stroke()                       // crisp inner line
    }
}
