//
//  TextInjector.swift
//  roam
//
//  Inserts text into the frontmost app's focused text field — the delivery half
//  of screen-aware dictation. Two strategies:
//
//   • insert(_:)      clipboard save → set → ⌘V → restore. Reliable across apps,
//                     used for the final dictation / generated reply.
//   • typeString(_:)  CGEvent Unicode injection ("types" characters). Handy for a
//                     live streaming feel; less reliable in some apps.
//
//  Requires Accessibility permission (already required by roam). The OS blocks
//  synthetic input into secure/password fields — that's expected; we just no-op.
//

import AppKit

@MainActor
enum TextInjector {

    /// Paste `text` into the focused field via the clipboard, preserving the
    /// user's existing clipboard string.
    static func insert(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        pressCommandV()

        // Restore the old clipboard after the target app has read the paste.
        let restore = previous
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let restore { pb.setString(restore, forType: .string) }
        }
    }

    /// Type `text` as synthetic Unicode key events (streaming feel). Posts the
    /// whole string in one keyDown/keyUp pair.
    static func typeString(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        var utf16 = Array(text.utf16)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }

        utf16.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Delete `count` characters before the caret (synthetic Backspace presses).
    /// Used to reconcile streaming dictation when the recognizer revises earlier words.
    static func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let deleteKey: CGKeyCode = 51 // Delete / Backspace
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    /// Synthesize ⌘V.
    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // 'v'

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
