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

    // Menu bar icon variants
    private var defaultIcon: NSImage?
    private var activeIcon: NSImage?
    private var pausedIcon: NSImage?

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

        // Load both icon variants
        if let path = Bundle.main.path(forResource: "menubar_icon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false
            defaultIcon = img
        }
        if let path = Bundle.main.path(forResource: "menubar_icon_green", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false
            activeIcon = img
        }
        if let path = Bundle.main.path(forResource: "menubar_icon_paused", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false
            pausedIcon = img
        }

        if let button = statusItem.button {
            button.image = defaultIcon ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Autoclaw")
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

        let widgetTitle = pillWindow.isVisible ? "Hide Widget" : "Show Widget"
        menu.addItem(withTitle: widgetTitle, action: #selector(toggleWidget), keyEquivalent: "")

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

    @objc private func toggleWidget() {
        if pillWindow.isVisible {
            pillWindow.orderOut(nil)
        } else {
            pillWindow.orderFront(nil)
        }
    }

    private func setupPillWindow() {
        pillWindow = PillWindow(appState: appState)
        // Don't show by default — toggle via menu bar
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
        hotkeyMonitor = GlobalHotkeyMonitor(
            onToggle: { [weak self] in self?.appState.toggleSession() },
            onPause:  { [weak self] in
                guard let s = self?.appState else { return }
                if s.lastEndedThread != nil {
                    // Session just ended — Fn resumes it
                    s.resumeEndedSession()
                    self?.showThreadToast()
                } else if s.sessionActive {
                    s.togglePause()
                } else {
                    s.toggleSession()
                }
            },
            onEnd:    { [weak self] in
                guard let s = self?.appState else { return }
                if !s.sessionActive && s.lastEndedThread != nil {
                    // Session already ended, toast showing — double-Option dismisses
                    self?.threadWindow.dismiss()
                    s.dismissEndedSession()
                } else {
                    s.endSession()
                }
            },
            onScreenshot: { [weak self] in self?.appState.addScreenshotToThread() },
            onCycleMode: { [weak self] in self?.appState.cycleRequestMode() }
        )
        hotkeyMonitor.start()
    }

    private func startServices() {
        appState.clipboardMonitor.start()
        appState.activeWindowService.start()
    }

    // MARK: - State Observation

    private func observeState() {
        // Swap menu bar icon based on session state (active/paused/inactive)
        Publishers.CombineLatest(appState.$sessionActive, appState.$sessionPaused)
            .removeDuplicates(by: { $0 == $1 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active, paused in
                guard let self else { return }
                let icon: NSImage?
                if active && paused {
                    icon = self.pausedIcon ?? self.defaultIcon
                } else if active {
                    icon = self.activeIcon ?? self.defaultIcon
                } else {
                    icon = self.defaultIcon
                }
                self.statusItem.button?.image = icon ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Autoclaw")
            }
            .store(in: &cancellables)

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

        // Re-render toast when executing state changes (for glow + icon update)
        appState.$isExecuting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.appState.showThread {
                    self.showThreadToast()
                }
            }
            .store(in: &cancellables)

        // Re-render toast as execution output streams in (throttled)
        appState.$executionOutput
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.appState.showThread && self.appState.isExecuting {
                    self.showThreadToast()
                }
            }
            .store(in: &cancellables)

        // Re-render toast when session ends (to show ended state)
        appState.$sessionActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if !active && !self.appState.threadMessages.isEmpty {
                    self.appState.showThread = true
                    self.showThreadToast()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Toast Presentation

    private func showThreadToast() {
        let isEnded = !appState.sessionActive && !appState.threadMessages.isEmpty

        let view = ThreadToastView(
            appState: appState,
            onApprove: { [weak self] in
                self?.appState.approveSuggestion()
                // Toast stays open — re-renders with executing state
            },
            onDirectExecute: { [weak self] in
                // Toast stays open — re-renders with executing state
                _ = self  // keep reference alive
            },
            onDismiss: { [weak self] in
                self?.threadWindow.dismiss()
                if isEnded {
                    self?.appState.dismissEndedSession()
                } else {
                    self?.appState.dismissThread()
                }
            },
            onResume: isEnded ? { [weak self] in
                self?.threadWindow.dismiss()
                self?.appState.resumeEndedSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.showThreadToast()
                }
            } : nil
        )

        threadWindow.show(with: view)

        // Enable file drag & drop on the thread toast
        threadWindow.onFilesDropped = { [weak self] urls in
            self?.appState.addAttachments(urls)
        }
        threadWindow.enableFileDrop()
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
