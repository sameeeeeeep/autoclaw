import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pillWindow: PillWindow!
    private var mainPanelWindow: MainPanelWindow!
    private var toastWindow: ToastWindow!
    private var projectPickerWindow: ToastWindow!
    private var clarificationWindow: ToastWindow!
    private var errorWindow: ToastWindow!
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
        toastWindow = ToastWindow()
        projectPickerWindow = ToastWindow()
        clarificationWindow = ToastWindow()
        clarificationWindow.allowsKeyboard = true  // needs text input
        errorWindow = ToastWindow()
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

        // Show task suggestion toast
        appState.$currentSuggestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestion in
                guard let self else { return }
                print("[Autoclaw] Observer: currentSuggestion changed — \(suggestion != nil ? "showing" : "nil")")
                if suggestion != nil {
                    self.showTaskToast()
                } else {
                    self.toastWindow.dismiss()
                }
            }
            .store(in: &cancellables)

        // Show clarification toast
        appState.$pendingClarification
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clarification in
                guard let self else { return }
                print("[Autoclaw] Observer: pendingClarification changed — \(clarification != nil ? "showing" : "nil")")
                if clarification != nil {
                    self.showClarificationToast()
                } else {
                    self.clarificationWindow.dismiss()
                }
            }
            .store(in: &cancellables)

        // Show error toast
        appState.$deductionError
            .sink { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.showErrorToast()
                } else {
                    self.errorWindow.dismiss()
                }
            }
            .store(in: &cancellables)

        // Auto dismiss toast on execution start
        appState.$isExecuting
            .filter { $0 }
            .sink { [weak self] _ in
                self?.toastWindow.dismiss()
            }
            .store(in: &cancellables)
    }

    // MARK: - Toast Presentation

    private func showTaskToast() {
        guard let suggestion = appState.currentSuggestion else { return }

        let view = TaskToastView(
            appState: appState,
            suggestion: suggestion,
            onApprove: { [weak self] in
                self?.toastWindow.dismiss()
                self?.appState.approveSuggestion()
                // Show main panel for execution output
                self?.mainPanelWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onDismiss: { [weak self] in
                self?.toastWindow.dismiss()
                self?.appState.dismissSuggestion()
            }
        )

        toastWindow.show(with: view)
    }

    private func showClarificationToast() {
        guard let clarification = appState.pendingClarification else { return }

        let view = ClarificationToastView(
            appState: appState,
            clarification: clarification,
            onRespond: { [weak self] answer in
                self?.clarificationWindow.dismiss()
                self?.appState.respondToClarification(answer)
            },
            onDismiss: { [weak self] in
                self?.clarificationWindow.dismiss()
                self?.appState.dismissClarification()
            }
        )

        clarificationWindow.show(with: view)
    }

    private func showErrorToast() {
        guard let error = appState.deductionError else { return }

        let view = ErrorToastView(
            message: error,
            onRetry: { [weak self] in
                self?.errorWindow.dismiss()
                self?.appState.dismissError()
                self?.appState.deduceTask()
            },
            onDismiss: { [weak self] in
                self?.errorWindow.dismiss()
                self?.appState.dismissError()
            }
        )

        errorWindow.show(with: view)
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
