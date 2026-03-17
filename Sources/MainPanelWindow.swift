import AppKit
import SwiftUI

final class MainPanelWindow: NSWindow {
    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Autoclaw"
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        center()

        let view = MainPanelView(appState: appState)
        contentView = NSHostingView(rootView: view)
    }
}
