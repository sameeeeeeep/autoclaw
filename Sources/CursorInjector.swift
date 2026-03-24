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

        // 3. Small delay for pasteboard to sync
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // 4. Simulate Cmd+V
        simulatePaste()

        // 5. Restore original clipboard after a delay
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        pasteboard.clearContents()
        for (typeRaw, data) in savedItems {
            let type = NSPasteboard.PasteboardType(typeRaw)
            pasteboard.setData(data, forType: type)
        }
    }

    // MARK: - Private

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
