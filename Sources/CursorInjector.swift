import Foundation
import CoreGraphics
import AppKit

// MARK: - Cursor Injector

/// Injects text at the current cursor position using the clipboard + Cmd+V approach.
/// More reliable than CGEvent character-by-character typing, handles Unicode correctly.
enum CursorInjector {

    /// Paste text at the current cursor position.
    /// Saves clipboard, sets text, simulates Cmd+V, restores clipboard.
    static func type(_ text: String) async {
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        // 2. Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Delay to let pasteboard sync AND target app regain focus
        // (our toast may have stolen focus momentarily)
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // 4. Simulate Cmd+V
        simulatePaste()

        // 5. Restore original clipboard after paste completes
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        pasteboard.clearContents()
        for (typeRaw, data) in savedItems {
            let type = NSPasteboard.PasteboardType(typeRaw)
            pasteboard.setData(data, forType: type)
        }
    }

    /// Select all text in current field (Cmd+A) then paste replacement text.
    /// Used for replacing raw transcription with enhanced version.
    static func selectAllAndReplace(_ text: String) async {
        let pasteboard = NSPasteboard.general

        // Save clipboard
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        // Set replacement text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Cmd+A (select all in field)
        simulateSelectAll()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Cmd+V (paste, replacing selection)
        simulatePaste()

        // Restore clipboard
        try? await Task.sleep(nanoseconds: 500_000_000)
        pasteboard.clearContents()
        for (typeRaw, data) in savedItems {
            let type = NSPasteboard.PasteboardType(typeRaw)
            pasteboard.setData(data, forType: type)
        }
    }

    // MARK: - Private

    private static func simulateSelectAll() {
        let aKeyCode: CGKeyCode = 0x00 // 'a' key
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: aKeyCode, keyDown: true) else { return }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: aKeyCode, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }

    private static func simulatePaste() {
        // Create Cmd+V key event
        let vKeyCode: CGKeyCode = 0x09 // 'v' key

        // Key down with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) else { return }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        // Key up with Cmd modifier
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }
}
