import Foundation
import CoreGraphics
import AppKit

// MARK: - Cursor Injector

/// Injects text at the current cursor position using the clipboard + Cmd+V approach.
/// More reliable than CGEvent character-by-character typing, handles Unicode correctly.
enum CursorInjector {

    /// Set to true while injecting so ClipboardMonitor ignores changes
    @MainActor static var isInjecting = false

    /// Paste text at the current cursor position.
    /// Sets text to clipboard, simulates Cmd+V. Leaves transcribed text on clipboard (useful).
    static func type(_ text: String) async {
        await MainActor.run { isInjecting = true }

        // Verify we have accessibility access
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("[CursorInjector] WARNING: App is NOT trusted for accessibility. CGEvent posting will fail silently.")
        }

        let pasteboard = NSPasteboard.general

        // Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Delay to let pasteboard sync AND target app regain focus
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Simulate Cmd+V
        simulatePaste()

        // Keep isInjecting true long enough for ClipboardMonitor to skip
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
        await MainActor.run { isInjecting = false }
    }

    /// Select all text in current field (Cmd+A) then paste replacement text.
    /// Used for replacing raw transcription with enhanced version.
    static func selectAllAndReplace(_ text: String) async {
        await MainActor.run { isInjecting = true }

        let pasteboard = NSPasteboard.general

        // Set replacement text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Cmd+A (select all in field)
        simulateSelectAll()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Cmd+V (paste, replacing selection)
        simulatePaste()

        // Keep isInjecting true long enough for ClipboardMonitor to skip
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
        await MainActor.run { isInjecting = false }
    }

    // MARK: - Private

    /// Create an event source for synthetic keyboard events.
    /// Using an explicit source (vs nil) is more reliable across app boundaries.
    private static func makeSource() -> CGEventSource? {
        CGEventSource(stateID: .combinedSessionState)
    }

    private static func simulateSelectAll() {
        let source = makeSource()
        let aKeyCode: CGKeyCode = 0x00 // 'a' key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: true) else {
            print("[CursorInjector] Failed to create Cmd+A keyDown event")
            return
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }

    private static func simulatePaste() {
        let source = makeSource()
        let vKeyCode: CGKeyCode = 0x09 // 'v' key

        // Key down with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            print("[CursorInjector] Failed to create Cmd+V keyDown event — accessibility permission missing?")
            return
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        // Key up with Cmd modifier
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }
}
