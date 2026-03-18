import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pillWindow: PillWindow!
    private var mainPanelWindow: MainPanelWindow!
    private var threadWindow: ToastWindow!
    private var projectPickerWindow: ToastWindow!
    private var hotkeyMonitor: GlobalHotkeyMonitor!
    private var cancellables = Set<AnyCancellable>()

    let appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupPillWindow()
        setupMainPanel()
        setupToastWindows()
        setupHotkey()
        startServices()
        observeState()
    }

    // MARK: - Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Autoclaw")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        if appState.sessionActive {
            let sessionItem = NSMenuItem(title: "Session: \(appState.currentSessionId?.prefix(8) ?? "active")…", action: nil, keyEquivalent: "")
            sessionItem.isEnabled = false
            menu.addItem(sessionItem)
            menu.addItem(withTitle: "End Session", action: #selector(endSession), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Start Session", action: #selector(startSession), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Autoclaw", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear menu so left-click works again next time
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }

    @objc private func endSession() { appState.endSession() }
    @objc private func startSession() { appState.startSession() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func setupPillWindow() {
        pillWindow = PillWindow(appState: appState)
        pillWindow.orderFront(nil)
    }

    private func setupMainPanel() {
        mainPanelWindow = MainPanelWindow(appState: appState)
    }

    private func setupToastWindows() {
        threadWindow = ToastWindow()
        threadWindow.allowsKeyboard = true  // needs text input
        projectPickerWindow = ToastWindow()
    }

    private func setupHotkey() {
        hotkeyMonitor = GlobalHotkeyMonitor { [weak self] in
            self?.appState.toggleSession()
        }
        hotkeyMonitor.start()
    }

    private func startServices() {
        appState.clipboardMonitor.start()
        appState.activeWindowService.start()
    }

    // MARK: - State Observation

    private func observeState() {
        // Show project picker toast when clipboard captured without project
        appState.$needsProjectSelection
            .removeDuplicates()
            .sink { [weak self] needs in
                guard let self else { return }
                if needs {
                    self.showProjectPickerToast()
                } else {
                    self.projectPickerWindow.dismiss()
                }
            }
            .store(in: &cancellables)

        // Show/dismiss thread toast
        appState.$showThread
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show {
                    self.showThreadToast()
                } else {
                    self.threadWindow.dismiss()
                }
            }
            .store(in: &cancellables)

        // Re-render thread toast when messages change
        appState.$threadMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self else { return }
                if self.appState.showThread && !messages.isEmpty {
                    self.showThreadToast()
                }
            }
            .store(in: &cancellables)

        // Also re-render when deducing state changes (for thinking indicator)
        appState.$isDeducing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.appState.showThread {
                    self.showThreadToast()
                }
            }
            .store(in: &cancellables)

        // Auto dismiss thread on execution start, show main panel
        appState.$isExecuting
            .filter { $0 }
            .sink { [weak self] _ in
                self?.mainPanelWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Toast Presentation

    private func showThreadToast() {
        let view = ThreadToastView(
            appState: appState,
            onApprove: { [weak self] in
                self?.threadWindow.dismiss()
                self?.appState.showThread = false
                self?.appState.approveSuggestion()
                self?.mainPanelWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onDismiss: { [weak self] in
                self?.threadWindow.dismiss()
                self?.appState.dismissThread()
            }
        )

        threadWindow.show(with: view)
    }

    private func showProjectPickerToast() {
        let view = ProjectPickerToastView(
            appState: appState,
            onSelect: { [weak self] project in
                self?.projectPickerWindow.dismiss()
                self?.appState.projectSelectedAfterClipboard(project)
            },
            onDismiss: { [weak self] in
                self?.projectPickerWindow.dismiss()
                self?.appState.needsProjectSelection = false
            }
        )

        projectPickerWindow.show(with: view)
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        if mainPanelWindow.isVisible {
            mainPanelWindow.orderOut(nil)
        } else {
            mainPanelWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
