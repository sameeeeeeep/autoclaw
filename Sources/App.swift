import SwiftUI

@main
struct AutoclawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                // Standard Edit menu — enables Cmd+C/V/X in text fields
                CommandGroup(replacing: .pasteboard) {
                    Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                        .keyboardShortcut("x")
                    Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                        .keyboardShortcut("c")
                    Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                        .keyboardShortcut("v")
                    Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                        .keyboardShortcut("a")
                }
            }
    }
}
