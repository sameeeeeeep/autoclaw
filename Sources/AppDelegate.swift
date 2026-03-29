import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainPanelWindow: MainPanelWindow!
    private var toastWindow: ToastWindow!
    private var projectPickerWindow: ToastWindow!
    // Legacy friction window kept for backward compat — unified toast handles both now
    private var frictionToastWindow: ToastWindow!
    private var theaterPIPWindow: TheaterPIPWindow!
    private var hotkeyMonitor: GlobalHotkeyMonitor!
    private var cancellables = Set<AnyCancellable>()

    // Menu bar icon variants
    private var defaultIcon: NSImage?
    private var activeIcon: NSImage?
    private var pausedIcon: NSImage?

    let appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.clear()
        DebugLog.log("[App] Launch started")
        setupMenuBar()
        setupMainPanel()
        setupToastWindows()
        setupHotkey()
        startServices()
        observeState()
        DebugLog.log("[App] Launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Kill TTS sidecar process so it doesn't orphan
        appState.transcribeService.dialogVoice.stopSidecar()
        DebugLog.log("[App] Terminated — sidecar stopped")
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

    private func setupMainPanel() {
        mainPanelWindow = MainPanelWindow(appState: appState)
    }

    private func setupToastWindows() {
        toastWindow = ToastWindow()
        projectPickerWindow = ToastWindow()
        frictionToastWindow = ToastWindow()  // legacy, kept for friction-only display
        theaterPIPWindow = TheaterPIPWindow()
    }

    private func setupHotkey() {
        hotkeyMonitor = GlobalHotkeyMonitor(
            onToggle: { [weak self] in
                // Left Shift → cycle mode
                guard let s = self?.appState else { return }
                s.cycleRequestMode()
                // Pre-warm audio when cycling to transcribe
                if s.requestMode == .transcribe {
                    s.voiceService.warmup()
                }
                // If toast is visible, re-render with new mode
                if s.showThread {
                    self?.showThreadToast()
                }
            },
            onPause:  { [weak self] in
                // Fn key — three states:
                // 1. Toast not visible → open toast in transcribe mode (no session yet)
                // 2. Toast visible, no session → start session + mode action (mic on)
                // 3. Session running → stop session (and mode-specific action)
                guard let s = self?.appState else { return }

                DebugLog.log("[Fn] pressed — showThread: \(s.showThread), sessionActive: \(s.sessionActive), isTranscribing: \(s.isTranscribing), mode: \(s.requestMode), transcribeStatus: \(s.transcribeStatus.label)")

                if !s.showThread {
                    // State 1: Toast closed → just open it in transcribe mode
                    s.requestMode = .transcribe
                    s.showThread = true
                    self?.showThreadToast()
                    // Fire pre-prompt immediately so user sees loading state
                    s.firePrePromptIfNeeded()
                } else if !s.sessionActive {
                    // State 2: Toast visible, no session → start session + mode action
                    s.startSession()
                    self?.showThreadToast()
                    // Auto-start mode-specific actions
                    switch s.requestMode {
                    case .learn:
                        if !s.isLearnRecording {
                            s.startLearnRecording()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self?.showThreadToast()
                            }
                        }
                    case .transcribe:
                        if !s.isTranscribing {
                            s.toggleTranscribe()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self?.showThreadToast()
                            }
                        }
                    default:
                        break
                    }
                } else {
                    // State 3: Session running → stop (including mode-specific actions)
                    switch s.requestMode {
                    case .transcribe where s.isTranscribing:
                        // Let transcribeService.stop() finish its async work
                        // It will transcribe remaining audio, clean, inject, enhance
                        // Do NOT call endSession() here — it would kill the async work
                        s.isTranscribing = false
                        s.transcribeService.stop()
                        DebugLog.log("[Fn] Transcribe stopping — letting async work finish")
                        return  // don't endSession yet, stop() handles everything
                    case .learn where s.isLearnRecording:
                        s.stopLearnRecording()
                        // Don't end session — let user review extracted steps
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self?.showThreadToast()
                        }
                        return
                    default:
                        break
                    }
                    s.endSession()
                }
            },
            onEnd:    { [weak self] in
                // Double-tap Left ⌥ → full dismiss (clean slate)
                guard let s = self?.appState else { return }
                // Stop any mode-specific action
                if s.isLearnRecording { s.stopLearnRecording() }
                // End session if active (this handles transcribe cleanup via forceReset)
                if s.sessionActive { s.endSession() }
                // Force reset transcribe even if session wasn't active
                s.transcribeService.forceReset()
                s.voiceService.whisperKitService.forceReset()
                s.voiceService.isListening = false
                s.isTranscribing = false
                // Dismiss toast + theater PIP and clear all state
                self?.toastWindow.dismiss()
                self?.theaterPIPWindow.dismiss()
                s.showThread = false
                s.lastEndedThread = nil
                s.threadMessages = []
                // Reset transcribe state for next session
                s.transcribeStatus = .idle
                s.transcribeRawText = ""
                s.transcribeCleanText = ""
                // Reset to transcribe mode so next Fn opens fresh
                s.requestMode = .transcribe
            },
            onScreenshot: { [weak self] in
                // ⌥+Z: dismiss toast without ending session (execution continues)
                guard let s = self?.appState else { return }
                if s.sessionActive {
                    self?.toastWindow.dismiss()
                    s.dismissThread()
                }
            },
            onCycleMode: { [weak self] in self?.appState.cycleRequestMode() },
            onVoiceToggle: { [weak self] in self?.appState.toggleVoice() }
        )
        hotkeyMonitor.start()
    }

    private func startServices() {
        appState.clipboardMonitor.start()
        appState.activeWindowService.start()

        // Pre-load WhisperKit model on launch (downloads once ~142MB, then instant)
        appState.voiceService.warmup()
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
                    self.toastWindow.dismiss()
                }
            }
            .store(in: &cancellables)

        // Show/dismiss friction toast via unified toast (analyze mode)
        appState.$frictionToastState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state != nil {
                    self.appState.requestMode = .analyze
                    self.appState.showThread = true
                    self.showThreadToast()
                } else if self.appState.requestMode == .analyze {
                    self.toastWindow.dismiss()
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

        // Re-render toast when transcribe status changes
        appState.$transcribeStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.appState.requestMode == .transcribe && self.appState.showThread {
                    self.showThreadToast()
                }
            }
            .store(in: &cancellables)

        // Theater PIP — show when dialog arrives, refit on updates.
        // Never auto-dismiss on empty — only explicit user dismiss (X button) or session end.
        appState.transcribeService.$sessionDialog
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dialog in
                guard let self else { return }
                guard AppSettings.shared.theaterMode else { return }
                guard !dialog.isEmpty else { return }  // ignore clears during refresh
                if self.theaterPIPWindow.isVisible {
                    self.theaterPIPWindow.refit()
                } else {
                    self.showTheaterPIP()
                }
            }
            .store(in: &cancellables)

        // Dismiss theater PIP when session ends or theater mode disabled
        appState.$sessionActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if !active {
                    self.theaterPIPWindow.dismiss()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Toast Presentation

    private func showThreadToast() {
        let isEnded = !appState.sessionActive && !appState.threadMessages.isEmpty

        let view = UnifiedToastView(
            appState: appState,
            onDirectExecute: { [weak self] in
                _ = self  // keep reference alive; toast re-renders via state
            },
            onDismiss: { [weak self] in
                self?.toastWindow.dismiss()
                if isEnded {
                    self?.appState.dismissEndedSession()
                } else {
                    self?.appState.dismissThread()
                }
            },
            onResume: isEnded ? { [weak self] in
                self?.toastWindow.dismiss()
                self?.appState.resumeEndedSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.showThreadToast()
                }
            } : { },
            // Friction callbacks (for analyze mode)
            onAutomate: { [weak self] in self?.appState.acceptFriction() },
            onRun: { [weak self] in self?.appState.runFriction() },
            onStop: { [weak self] in self?.appState.dismissFriction() },
            onOpen: { [weak self] in self?.appState.dismissFriction() },
            onRetry: { [weak self] in self?.appState.runFriction() }
        )

        toastWindow.show(with: view)

        // Enable file drag & drop
        toastWindow.onFilesDropped = { [weak self] urls in
            self?.appState.addAttachments(urls)
        }
        toastWindow.enableFileDrop()
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

    private func showTheaterPIP() {
        // Auto-launch TTS sidecar if not running
        appState.transcribeService.dialogVoice.launchSidecarIfNeeded()

        let view = TheaterPIPView(
            transcribeService: appState.transcribeService,
            onDismiss: { [weak self] in
                self?.theaterPIPWindow.dismiss()
            }
        )
        theaterPIPWindow.show(with: view)
    }

    private func showFrictionToast() {
        guard let state = appState.frictionToastState else {
            frictionToastWindow.dismiss()
            return
        }
        var toast = FrictionToastView(state: state)
        toast.onAutomate = { [weak self] in self?.appState.acceptFriction() }
        toast.onEditSteps = {}
        toast.onRun = { [weak self] in self?.appState.runFriction() }
        toast.onStop = { [weak self] in self?.appState.dismissFriction() }
        toast.onOpen = { [weak self] in self?.appState.dismissFriction() }
        toast.onRetry = { [weak self] in self?.appState.runFriction() }
        toast.onDismiss = { [weak self] in self?.appState.dismissFriction() }
        frictionToastWindow.show(with: toast)
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
