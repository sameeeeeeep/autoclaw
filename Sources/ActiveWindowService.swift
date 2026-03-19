import AppKit
import Combine

@MainActor
final class ActiveWindowService: ObservableObject {
    @Published var appName = ""
    @Published var windowTitle = ""
    @Published var browserURL = ""  // active tab URL for Chrome/Safari/Arc

    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        appName = frontApp.localizedName ?? ""

        let pid = frontApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowValue: AnyObject?
        AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue)

        if let window = windowValue {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
            windowTitle = titleValue as? String ?? ""
        } else {
            windowTitle = ""
        }

        // Get browser tab URL via AppleScript (Chrome, Safari, Arc)
        let browserApps = ["Google Chrome", "Safari", "Arc"]
        if browserApps.contains(appName) {
            browserURL = Self.getBrowserURL(for: appName) ?? ""
        } else {
            browserURL = ""
        }
    }

    /// Get the active tab URL from a browser using AppleScript
    static func getBrowserURL(for browser: String) -> String? {
        let script: String
        switch browser {
        case "Google Chrome":
            script = "tell application \"Google Chrome\" to get URL of active tab of first window"
        case "Safari":
            script = "tell application \"Safari\" to get URL of front document"
        case "Arc":
            script = "tell application \"Arc\" to get URL of active tab of first window"
        default:
            return nil
        }

        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
