import AppKit
import Combine

@MainActor
final class ActiveWindowService: ObservableObject {
    @Published var appName = ""
    @Published var windowTitle = ""

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
    }
}
