//
//  DictationShortcutMonitor.swift
//  roam
//
//  Global press-and-hold monitor for screen-aware dictation. Fires on
//  Control + Command. Modifier-only, like push-to-talk: press to start recording,
//  release to finish.
//
//  Listen-only CGEvent tap on .flagsChanged — needs Accessibility permission but
//  never consumes the keys. Deliberately disjoint from the ⌃⌥ spatial chord, and
//  off Fn so it doesn't collide with other dictation tools (e.g. Wispr Flow).
//
//  To rebind, edit `requiredModifiers` below — e.g. [.control, .shift].
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class DictationShortcutMonitor: ObservableObject {
    enum Transition { case pressed, released }

    let transitionPublisher = PassthroughSubject<Transition, Never>()

    /// Control + Command. Edit to rebind (e.g. [.control, .shift]).
    private static let requiredModifiers: NSEvent.ModifierFlags = [.control, .command]

    @Published private(set) var isPressed = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    deinit { stop() }

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue

        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<DictationShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(eventType: eventType, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Dictation hotkey: couldn't create CGEvent tap")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            print("⚠️ Dictation hotkey: couldn't create run loop source")
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        isPressed = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func handle(eventType: CGEventType, event: CGEvent) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        guard eventType == .flagsChanged else { return }

        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)
        // Require Control+Command both down, and not the ⌥ used by the spatial chord.
        let nowPressed = flags.contains(Self.requiredModifiers) && !flags.contains(.option)

        if nowPressed && !isPressed {
            isPressed = true
            transitionPublisher.send(.pressed)
        } else if !nowPressed && isPressed {
            isPressed = false
            transitionPublisher.send(.released)
        }
    }
}
