import Foundation
import CoreGraphics
import AppKit

// MARK: - Cursor Injector

/// Injects text at the current cursor position using the clipboard + Cmd+V approach.
/// More reliable than CGEvent character-by-character typing, handles Unicode correctly.
enum CursorInjector {

    /// Set to true while injecting so ClipboardMonitor ignores changes
    @MainActor static var isInjecting = false

    /// The app that was frontmost before Autoclaw's toast appeared.
    /// Set by AppDelegate/AppState when capturing the target app context.
    @MainActor static var targetApp: NSRunningApplication?

    /// Paste text at the current cursor position.
    /// Sets text to clipboard, re-focuses target app, simulates Cmd+V.
    static func type(_ text: String) async {
        await MainActor.run { isInjecting = true }
        DebugLog.log("[CursorInjector] type() called (\(text.count) chars): \(text.prefix(80))...")

        let pasteboard = NSPasteboard.general

        // Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Re-focus the target app before pasting
        let pid = await activateTargetApp()

        // Delay to let app come to foreground + pasteboard sync
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // Simulate Cmd+V — post to target app's PID if available
        simulatePaste(targetPID: pid)

        // Keep isInjecting true long enough for ClipboardMonitor to skip
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
        await MainActor.run { isInjecting = false }
    }

    /// Select all text in current field (Cmd+A) then paste replacement text.
    /// Used for replacing raw transcription with enhanced version.
    static func selectAllAndReplace(_ text: String) async {
        await MainActor.run { isInjecting = true }
        DebugLog.log("[CursorInjector] selectAllAndReplace() called (\(text.count) chars)")

        let pasteboard = NSPasteboard.general

        // Set replacement text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Re-focus the target app before pasting
        let pid = await activateTargetApp()

        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // Cmd+A (select all in field)
        simulateSelectAll(targetPID: pid)
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // Cmd+V (paste, replacing selection)
        simulatePaste(targetPID: pid)

        // Keep isInjecting true long enough for ClipboardMonitor to skip
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
        await MainActor.run { isInjecting = false }
    }

    // MARK: - Target App Focus

    /// Re-activate the app the user was in before Autoclaw's toast appeared.
    /// Returns the PID for targeted event posting.
    @discardableResult
    private static func activateTargetApp() async -> pid_t? {
        let app: NSRunningApplication? = await MainActor.run {
            if let target = targetApp, !target.isTerminated {
                return target
            }
            // Fallback: find the frontmost app that isn't us
            return NSWorkspace.shared.runningApplications.first {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
        }

        guard let app else {
            DebugLog.log("[CursorInjector] No target app found — paste will go to frontmost app")
            return nil
        }

        let pid = app.processIdentifier
        DebugLog.log("[CursorInjector] Activating target: \(app.localizedName ?? "unknown") (pid: \(pid), bundle: \(app.bundleIdentifier ?? "?"))")

        app.activate()
        // Give the app time to actually come to the foreground
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Verify it actually came to front
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == pid {
            DebugLog.log("[CursorInjector] Target app is now frontmost ✓")
        } else {
            DebugLog.log("[CursorInjector] WARNING: Target app did NOT become frontmost. Front app: \(frontmost?.localizedName ?? "none") (pid: \(frontmost?.processIdentifier ?? 0))")
            // Try one more time with a longer delay
            app.activate()
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms more
        }

        return pid
    }

    // MARK: - Private

    /// Create an event source for synthetic keyboard events.
    private static func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        if source == nil {
            DebugLog.log("[CursorInjector] Failed to create CGEventSource — accessibility permission missing?")
        }
        return source
    }

    private static func simulateSelectAll(targetPID: pid_t? = nil) {
        let source = makeSource()
        let aKeyCode: CGKeyCode = 0x00 // 'a' key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: true) else {
            DebugLog.log("[CursorInjector] Failed to create Cmd+A keyDown event")
            return
        }
        keyDown.flags = .maskCommand

        if let pid = targetPID {
            keyDown.postToPid(pid)
        } else {
            keyDown.post(tap: .cghidEventTap)
        }

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        if let pid = targetPID {
            keyUp.postToPid(pid)
        } else {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private static func simulatePaste(targetPID: pid_t? = nil) {
        let source = makeSource()
        let vKeyCode: CGKeyCode = 0x09 // 'v' key

        // Key down with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            DebugLog.log("[CursorInjector] Failed to create Cmd+V keyDown event — accessibility permission missing?")
            return
        }
        keyDown.flags = .maskCommand

        if let pid = targetPID {
            keyDown.postToPid(pid)
            DebugLog.log("[CursorInjector] Posted Cmd+V keyDown to pid \(pid)")
        } else {
            keyDown.post(tap: .cghidEventTap)
            DebugLog.log("[CursorInjector] Posted Cmd+V keyDown to cghidEventTap (no target pid)")
        }

        // Key up with Cmd modifier
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        if let pid = targetPID {
            keyUp.postToPid(pid)
        } else {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
