import SwiftUI
import Combine

// MARK: - Model Selection

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku = "haiku"
    case sonnet = "sonnet"
    case opus = "opus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus:   return "Opus"
        }
    }

    var shortLabel: String {
        switch self {
        case .haiku:  return "H"
        case .sonnet: return "S"
        case .opus:   return "O"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Services
    let clipboardMonitor = ClipboardMonitor()
    let activeWindowService = ActiveWindowService()
    let taskDeductionService = TaskDeductionService()
    let claudeCodeRunner = ClaudeCodeRunner()
    let projectStore = ProjectStore()
    let sessionStore = SessionStore()
    let workflowRecorder = WorkflowRecorder()
    let workflowStore = WorkflowStore()
    let voiceService = VoiceService()

    // MARK: - ARIA Intelligence Layer
    let capabilityMap = CapabilityMap()
    let fileActivityMonitor = FileActivityMonitor()
    let browserBridge = BrowserBridge()
    private(set) var frictionDetector: FrictionDetector!
    private(set) var capabilityDiscovery: CapabilityDiscovery!
    private(set) var keyFrameAnalyzer: KeyFrameAnalyzer!

    // MARK: - Model & Project Preferences
    @Published var selectedModel: ClaudeModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "autoclaw_selected_model") }
    }
    @Published var selectedProject: Project? {
        didSet {
            if let p = selectedProject {
                UserDefaults.standard.set(p.id.uuidString, forKey: "autoclaw_last_project_id")
            }
        }
    }

    // MARK: - Session State
    @Published var sessionActive = false
    @Published var sessionPaused = false
    @Published var needsProjectSelection = false
    @Published var currentSessionId: String?
    @Published var currentThread: SessionThread?

    // MARK: - Request Mode
    @Published var requestMode: RequestMode = .task

    func cycleRequestMode() {
        let all = RequestMode.allCases
        guard let idx = all.firstIndex(of: requestMode) else { return }
        let next = all[(all.distance(from: all.startIndex, to: idx) + 1) % all.count]
        requestMode = next
        print("[Autoclaw] Request mode → \(next.rawValue)")
    }

    // MARK: - Thread (the chat thread in the toast)
    @Published var threadMessages: [ThreadMessage] = []
    @Published var showThread = false

    // MARK: - Panel Navigation
    @Published var viewingThread: SessionThread?  // thread selected in Threads tab for detail view

    // MARK: - Task Flow
    @Published var currentSuggestion: TaskSuggestion?
    @Published var isDeducing = false
    @Published var isExecuting = false
    @Published var executionOutput = ""
    @Published var deductionError: String?
    var executionTask: Task<Void, Never>?  // cancellable execution task

    // MARK: - Clarification Flow
    @Published var pendingClarification: Clarification?

    // MARK: - Context
    @Published var lastClipboard = ""
    @Published var clipboardCapturedApp = ""
    @Published var clipboardCapturedWindow = ""
    @Published var activeApp = ""
    @Published var activeWindowTitle = ""

    // MARK: - Status (shown in sidebar canvas)
    @Published var statusLine = "Ready"

    // MARK: - Learn Mode
    @Published var isLearnRecording = false
    @Published var currentRecording: WorkflowRecording?
    @Published var extractedSteps: [WorkflowStep] = []
    @Published var isExtractingSteps = false
    @Published var workflowNameDraft = ""

    // MARK: - Voice Mode
    @Published var isVoiceListening = false
    @Published var liveTranscript = ""
    @Published var pendingVoiceText = ""  // accumulated transcript, user edits + sends

    // MARK: - ARIA Friction Detection
    @Published var activeFriction: FrictionDetector.FrictionSignal?

    // MARK: - Chrome Extension (DOM events from WebSocket)
    var browserEventBuffer: [BrowserDOMEvent] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Restore saved model preference (default: haiku)
        if let savedModel = UserDefaults.standard.string(forKey: "autoclaw_selected_model"),
           let model = ClaudeModel(rawValue: savedModel) {
            self.selectedModel = model
        } else {
            self.selectedModel = .haiku
        }

        // Restore last-used project
        if let savedId = UserDefaults.standard.string(forKey: "autoclaw_last_project_id"),
           let uuid = UUID(uuidString: savedId) {
            self.selectedProject = projectStore.projects.first(where: { $0.id == uuid })
        }

        // Initialize ARIA intelligence layer
        self.frictionDetector = FrictionDetector(capabilityMap: capabilityMap)
        self.capabilityDiscovery = CapabilityDiscovery(runner: claudeCodeRunner, capabilityMap: capabilityMap)
        self.keyFrameAnalyzer = KeyFrameAnalyzer(captureStream: workflowRecorder.captureStream)

        // Connect key frame analyzer to friction detector for richer context
        frictionDetector.keyFrameAnalyzer = keyFrameAnalyzer

        setupBindings()
        setupVoice()
        setupARIA()
    }

    private func setupVoice() {
        // Forward live transcript to published state
        voiceService.$isListening
            .assign(to: &$isVoiceListening)

        voiceService.$currentTranscript
            .assign(to: &$liveTranscript)

        // When transcript is committed, populate the input field for user to review/edit/send
        voiceService.onTranscriptReady = { [weak self] text in
            Task { @MainActor in
                guard let self = self, self.sessionActive else { return }
                // Append to pending voice text — user presses enter to send
                if self.pendingVoiceText.isEmpty {
                    self.pendingVoiceText = text
                } else {
                    self.pendingVoiceText += " " + text
                }
                self.showThread = true
                self.statusLine = "Voice captured"
                print("[Autoclaw] Voice transcript → input: \(text.prefix(60))")
            }
        }
    }

    private func setupARIA() {
        // Scan installed MCP tools to build the capability map
        capabilityMap.scanInstalledTools()

        // Wire workflow matcher + saved workflows into friction detector
        let matcher = WorkflowMatcher()
        frictionDetector.workflowMatcher = matcher
        frictionDetector.savedWorkflows = workflowStore.workflows

        // Keep friction detector + key frame analyzer in sync with saved workflows
        workflowStore.$workflows
            .sink { [weak self] workflows in
                self?.frictionDetector.savedWorkflows = workflows
                // Build summaries for Haiku vision recognition
                self?.keyFrameAnalyzer.savedWorkflowSummaries = workflows.map { wf in
                    "- \"\(wf.name)\": \(wf.steps.map(\.description).joined(separator: " → "))"
                }.joined(separator: "\n")
            }
            .store(in: &cancellables)

        // Wire Haiku workflow recognition → friction detector
        keyFrameAnalyzer.onWorkflowRecognized = { [weak self] workflowName, confidence in
            guard let self = self else { return }
            // Find the matching saved workflow
            guard let workflow = self.workflowStore.workflows.first(where: { $0.name == workflowName }) else { return }

            let signal = FrictionDetector.FrictionSignal(
                timestamp: Date(),
                pattern: .recognizedWorkflow,
                involvedApps: workflow.steps.map(\.tool).unique(),
                description: "This looks like your '\(workflowName)' workflow",
                capability: nil,
                suggestion: "I recognized '\(workflowName)' — want me to run it for you?",
                confidence: confidence,
                isActionable: true,
                matchedWorkflow: workflow
            )
            self.frictionDetector.surfaceExternal(signal)
        }

        // Wire file activity monitor into friction detector + key frame analyzer
        fileActivityMonitor.onFileEvent = { [weak self] fileEvent in
            self?.frictionDetector.recordFileEvent(fileEvent)
            self?.keyFrameAnalyzer.onFileEvent(app: fileEvent.sourceApp ?? "unknown")
        }

        // Wire friction detection → surface offers to user
        frictionDetector.onFrictionDetected = { [weak self] signal in
            guard let self = self, self.sessionActive else { return }
            self.activeFriction = signal

            // Surface as a thread message (Gate 0: "I noticed X, want me to help?")
            self.threadMessages.append(.frictionOffer(signal: signal))
            self.showThread = true
            self.statusLine = signal.suggestion

            print("[Autoclaw/ARIA] Friction detected: \(signal.description)")

            // If it's a recognized workflow, log the match
            if signal.pattern == .recognizedWorkflow, let wf = signal.matchedWorkflow {
                print("[Autoclaw/ARIA] Matched learned workflow: '\(wf.name)' (\(wf.steps.count) steps)")
            }

            // If no installed capability, trigger discovery in background
            if !signal.isActionable, signal.involvedApps.count >= 2 {
                Task {
                    let _ = await self.capabilityDiscovery.discover(
                        sourceApp: signal.involvedApps[0],
                        targetApp: signal.involvedApps[1],
                        frictionDescription: signal.description
                    )
                }
            }
        }

        // Start browser bridge WebSocket server (always on, lightweight)
        browserBridge.start()

        // Wire DOM events from Chrome extension into the event buffer
        browserBridge.onDOMEvent = { [weak self] event in
            guard let self = self else { return }
            // Buffer events during learn mode recording
            if self.isLearnRecording {
                self.browserEventBuffer.append(event)
                // Also surface in the thread as a learn event
                let workflowEvent = WorkflowEvent(
                    type: .click,
                    app: "Chrome",
                    window: event.pageTitle ?? "",
                    description: self.domEventDescription(event),
                    data: event.value,
                    ocrContext: nil,
                    elapsed: 0
                )
                self.threadMessages.append(.learnEvent(event: workflowEvent))
            }
        }
    }

    /// Human-readable description of a DOM event for thread display
    private func domEventDescription(_ event: BrowserDOMEvent) -> String {
        switch event.type {
        case .click:
            let target = event.elementText ?? event.selector ?? "element"
            let page = event.pageTitle ?? event.url ?? ""
            return "Clicked '\(target)' on \(page)"
        case .input:
            let field = event.fieldName ?? "field"
            let value = event.value ?? ""
            return "Typed '\(value)' in \(field)"
        case .navigate:
            return "Navigated to \(event.url ?? "page")"
        case .submit:
            return "Submitted form on \(event.pageTitle ?? event.url ?? "page")"
        case .select:
            let field = event.fieldName ?? "dropdown"
            return "Selected '\(event.value ?? "")' in \(field)"
        }
    }

    private func setupBindings() {
        clipboardMonitor.$latestContent
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .sink { [weak self] content in
                Task { @MainActor in
                    self?.handleClipboardChange(content)
                }
            }
            .store(in: &cancellables)

        activeWindowService.$appName
            .assign(to: &$activeApp)

        activeWindowService.$windowTitle
            .assign(to: &$activeWindowTitle)

        // Update context chip in thread when active app changes during session
        activeWindowService.$appName
            .removeDuplicates()
            .sink { [weak self] app in
                Task { @MainActor in
                    self?.handleContextChange(app: app)
                }
            }
            .store(in: &cancellables)
    }

    private func handleContextChange(app: String) {
        guard sessionActive, !app.isEmpty else { return }
        let window = activeWindowTitle

        // Use resolved web app name instead of raw browser name
        let effectiveApp = activeWindowService.effectiveAppName
        let effectiveSection = activeWindowService.effectiveSection
        let url = activeWindowService.browserURL

        // Forward to learn recorder if active (uses effective app name)
        forwardToRecorderIfNeeded(app: effectiveApp, window: window)

        // Feed the friction detector
        frictionDetector.recordAppSwitch(
            app: effectiveApp,
            section: effectiveSection,
            url: url.isEmpty ? nil : url
        )

        // Capture key frame on app switch for richer context
        keyFrameAnalyzer.onAppSwitch(app: effectiveApp)

        // Update file activity monitor's app context
        fileActivityMonitor.updateActiveApp(effectiveApp)

        // Replace existing context message or add new one (show resolved app name)
        let displayApp = effectiveApp
        if let idx = threadMessages.lastIndex(where: {
            if case .context = $0 { return true }; return false
        }) {
            threadMessages[idx] = .context(app: displayApp, window: window)
        } else {
            threadMessages.append(.context(app: displayApp, window: window))
        }
    }

    // MARK: - Session

    func toggleSession() {
        if sessionActive {
            endSession()
        } else {
            startSession()
        }
    }

    func startSession() {
        sessionActive = true
        currentSessionId = UUID().uuidString
        currentSuggestion = nil
        executionOutput = ""
        deductionError = nil
        pendingClarification = nil
        needsProjectSelection = false
        threadMessages = []
        statusLine = "Session started"

        // Always create thread — attach project now or later
        if let sid = currentSessionId {
            let projectId = selectedProject?.id ?? UUID()
            currentThread = sessionStore.createThread(sessionId: sid, projectId: projectId)
        }

        // Start ARIA passive observation
        let projectId = selectedProject?.id ?? UUID()
        workflowRecorder.startPassiveObserving(projectId: projectId)
        fileActivityMonitor.start()
        keyFrameAnalyzer.start()

        // Start the screen capture stream for key frame analysis + click detection
        Task {
            await workflowRecorder.captureStream.start()

            // Wire click events → key frame analyzer (when not in learn mode)
            workflowRecorder.captureStream.onClickCaptured = { [weak self] frame, cursorLocation, screenSize in
                guard let self = self, !self.isLearnRecording else { return }
                let effectiveApp = self.activeWindowService.effectiveAppName
                Task { @MainActor in
                    self.keyFrameAnalyzer.onClick(app: effectiveApp, cursorPosition: cursorLocation)
                }
            }
        }

        // Add initial context chip and show toast immediately
        let effectiveApp = activeWindowService.effectiveAppName
        if !effectiveApp.isEmpty {
            threadMessages.append(.context(app: effectiveApp, window: activeWindowTitle))
        }
        showThread = true

        print("[Autoclaw] Session started: \(currentSessionId ?? "?")")
    }

    func pauseSession() {
        guard sessionActive, !sessionPaused else { return }
        sessionPaused = true
        statusLine = "Paused"
        print("[Autoclaw] Session paused: \(currentSessionId ?? "?")")
    }

    func resumeSessionFromPause() {
        guard sessionActive, sessionPaused else { return }
        sessionPaused = false
        statusLine = "Session active"
        print("[Autoclaw] Session resumed from pause: \(currentSessionId ?? "?")")
    }

    func togglePause() {
        if sessionPaused {
            resumeSessionFromPause()
        } else {
            pauseSession()
        }
    }

    /// Resume an existing session thread
    func resumeSession(thread: SessionThread) {
        sessionActive = true
        currentSessionId = thread.id.uuidString
        currentThread = thread
        currentSuggestion = nil
        executionOutput = ""
        deductionError = nil
        pendingClarification = nil
        needsProjectSelection = false
        threadMessages = []
        showThread = false
        statusLine = "Resumed: \(thread.title)"

        // Set the project to match the thread's project
        if let project = projectStore.projects.first(where: { $0.id == thread.projectId }) {
            selectedProject = project
        }

        sessionStore.updateThread(id: thread.id)
        print("[Autoclaw] Session resumed: \(currentSessionId ?? "?") — \(thread.title)")
    }

    /// The thread from the most recently ended session, kept for resume
    @Published var lastEndedThread: SessionThread?

    func endSession() {
        let ended = currentSessionId

        // Stop any running execution
        executionTask?.cancel()
        executionTask = nil

        // Stop voice if listening
        if voiceService.isListening {
            voiceService.stopListening()
        }

        // Stop learn recording if active
        if isLearnRecording {
            workflowRecorder.discardRecording()
            isLearnRecording = false
        }

        // Stop ARIA passive observation
        workflowRecorder.stopPassiveObserving()
        fileActivityMonitor.stop()
        keyFrameAnalyzer.stop()
        keyFrameAnalyzer.cleanup()
        activeFriction = nil

        // Stop capture stream (if not in learn mode, which manages its own lifecycle)
        if !isLearnRecording {
            workflowRecorder.captureStream.onClickCaptured = nil
            workflowRecorder.captureStream.stop()
        }

        sessionActive = false
        sessionPaused = false
        currentSuggestion = nil
        isDeducing = false
        isExecuting = false
        executionOutput = ""
        deductionError = nil
        pendingClarification = nil
        needsProjectSelection = false
        pendingVoiceText = ""
        liveTranscript = ""

        // Persist thread messages before clearing session
        if let thread = currentThread, !threadMessages.isEmpty {
            sessionStore.saveMessages(threadMessages, for: thread.id)
            print("[Autoclaw] Persisted \(threadMessages.count) messages for session \(thread.id)")
        }

        currentSessionId = nil

        // Keep thread + messages visible so the toast shows "session ended" state
        lastEndedThread = currentThread
        currentThread = nil
        // Don't clear threadMessages or showThread — let the toast stay with resume/dismiss
        statusLine = "Ready"

        print("[Autoclaw] Session ended: \(ended ?? "?")")
    }

    /// Dismiss the ended-session toast completely
    func dismissEndedSession() {
        lastEndedThread = nil
        threadMessages = []
        showThread = false
    }

    /// Resume from the ended session — keeps existing thread messages & toast visible
    func resumeEndedSession() {
        guard let thread = lastEndedThread else { return }
        lastEndedThread = nil

        // Resume the session WITHOUT clearing messages or toggling showThread
        sessionActive = true
        sessionPaused = false
        currentSessionId = thread.id.uuidString
        currentThread = thread
        currentSuggestion = nil
        executionOutput = ""
        deductionError = nil
        pendingClarification = nil
        needsProjectSelection = false
        statusLine = "Resumed: \(thread.title)"

        // Set project
        if let project = projectStore.projects.first(where: { $0.id == thread.projectId }) {
            selectedProject = project
        }

        sessionStore.updateThread(id: thread.id)

        // Keep the toast visible — don't toggle showThread off→on
        showThread = true

        print("[Autoclaw] Session resumed from ended state: \(currentSessionId ?? "?") — \(thread.title)")
    }

    // MARK: - Clipboard -> Thread (no longer auto-deduces)

    private func handleClipboardChange(_ content: String) {
        guard sessionActive, !isDeducing, !isExecuting else { return }

        // Use resolved app name for clipboard source
        let effectiveApp = activeWindowService.effectiveAppName
        let effectiveSection = activeWindowService.effectiveSection

        lastClipboard = content
        clipboardCapturedApp = effectiveApp
        clipboardCapturedWindow = activeWindowTitle

        // Forward to learn recorder if active
        forwardClipboardToRecorderIfNeeded(content: content, app: effectiveApp, window: activeWindowTitle)

        // Feed the friction detector
        frictionDetector.recordClipboard(
            content: content,
            sourceApp: effectiveApp,
            sourceSection: effectiveSection
        )

        // Capture key frame on clipboard for context
        keyFrameAnalyzer.onClipboard(app: effectiveApp)

        if selectedProject == nil {
            // Auto-select the only project if there's exactly one
            if projectStore.projects.count == 1 {
                selectedProject = projectStore.projects[0]
            } else {
                needsProjectSelection = true
                statusLine = "Select a project"
                return
            }
        }

        needsProjectSelection = false

        // Append clipboard entry to thread instead of auto-deducing
        let msg = ThreadMessage.clipboard(
            content: content,
            app: clipboardCapturedApp,
            window: clipboardCapturedWindow
        )
        threadMessages.append(msg)
        showThread = true
        statusLine = "Clipboard captured"
        print("[Autoclaw] Clipboard appended to thread (\(threadMessages.count) messages)")
    }

    func projectSelectedAfterClipboard(_ project: Project) {
        selectedProject = project
        needsProjectSelection = false

        // Reassign thread to the selected project (was placeholder UUID)
        if let thread = currentThread {
            sessionStore.reassignProject(id: thread.id, projectId: project.id)
            if let updated = sessionStore.threads.first(where: { $0.id == thread.id }) {
                currentThread = updated
            }
        } else if let sid = currentSessionId {
            currentThread = sessionStore.createThread(sessionId: sid, projectId: project.id)
        }

        // Re-process the pending clipboard now that we have a project
        if !lastClipboard.isEmpty {
            let msg = ThreadMessage.clipboard(
                content: lastClipboard,
                app: clipboardCapturedApp,
                window: clipboardCapturedWindow
            )
            threadMessages.append(msg)
            showThread = true
            statusLine = "Clipboard captured"
        }
    }

    // MARK: - Thread Actions

    /// User typed a message in the thread input
    func sendMessage(_ text: String) {
        threadMessages.append(.userMessage(text: text))
        sendToHaiku()
    }

    /// Send accumulated context to Haiku for deduction
    func sendToHaiku() {
        guard let project = selectedProject else { return }

        // Gather context from thread
        var clipboardEntries: [ClipboardEntry] = []
        var userMessages: [String] = []
        var screenshotPaths: [String] = []
        var attachmentPaths: [String] = []

        for msg in threadMessages {
            switch msg {
            case .clipboard(_, let content, let app, let window, _):
                clipboardEntries.append(ClipboardEntry(content: content, app: app, window: window))
            case .userMessage(_, let text, _):
                userMessages.append(text)
            case .screenshot(_, let path, _):
                screenshotPaths.append(path)
            case .attachment(_, let path, _, _, _):
                attachmentPaths.append(path)
            default:
                break
            }
        }

        guard !clipboardEntries.isEmpty || !userMessages.isEmpty || !attachmentPaths.isEmpty else { return }

        isDeducing = true
        currentSuggestion = nil
        deductionError = nil
        pendingClarification = nil
        statusLine = "Analyzing..."

        let context = TaskContext(
            clipboardEntries: clipboardEntries,
            userMessages: userMessages,
            screenshotPaths: screenshotPaths,
            attachmentPaths: attachmentPaths,
            project: project
        )

        Task { @MainActor in
            do {
                let suggestion = try await taskDeductionService.deduce(context: context, model: self.selectedModel)

                if suggestion.needsClarification {
                    print("[Autoclaw] Haiku needs clarification: \(suggestion.clarification?.question ?? "?")")
                    self.pendingClarification = suggestion.clarification
                    self.currentSuggestion = nil
                    // Show clarification as a haiku message in thread
                    self.threadMessages.append(.haiku(suggestion: suggestion))
                    self.statusLine = "Needs info"
                } else {
                    print("[Autoclaw] Haiku suggestion: \(suggestion.title)")
                    self.currentSuggestion = suggestion
                    self.pendingClarification = nil
                    self.threadMessages.append(.haiku(suggestion: suggestion))
                    self.statusLine = suggestion.title
                }
            } catch {
                print("[Autoclaw] Deduction error: \(error.localizedDescription)")
                self.deductionError = error.localizedDescription
                self.currentSuggestion = nil
                self.pendingClarification = nil
                self.threadMessages.append(.error(message: error.localizedDescription))
                self.statusLine = "Deduction failed"
            }
            self.isDeducing = false
        }
    }

    /// Add a screenshot to the thread context
    func addScreenshotToThread() {
        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else {
            print("[Autoclaw] Failed to capture screenshot for thread")
            return
        }

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let maxW: CGFloat = 1024
        let scale = srcW > maxW ? maxW / srcW : 1.0
        let dstW = Int(srcW * scale)
        let dstH = Int(srcH * scale)

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: dstW, height: dstH))

        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dstW,
            pixelsHigh: dstH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        nsImage.draw(in: NSRect(x: 0, y: 0, width: dstW, height: dstH))
        NSGraphicsContext.restoreGraphicsState()

        guard let jpegData = resized.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return }

        let tmpDir = NSTemporaryDirectory()
        let filename = "autoclaw_thread_\(UUID().uuidString.prefix(8)).jpg"
        let path = (tmpDir as NSString).appendingPathComponent(filename)

        do {
            try jpegData.write(to: URL(fileURLWithPath: path))
            threadMessages.append(.screenshot(path: path))
            showThread = true
            let sizeKB = jpegData.count / 1024
            print("[Autoclaw] Thread screenshot saved: \(path) (\(sizeKB)KB)")
        } catch {
            print("[Autoclaw] Failed to write thread screenshot: \(error)")
        }
    }

    // MARK: - File Attachments

    func addAttachments(_ urls: [URL]) {
        for url in urls {
            guard url.isFileURL else { continue }
            let path = url.path
            let name = url.lastPathComponent
            let size: Int64 = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            threadMessages.append(.attachment(path: path, name: name, size: size))
            print("[Autoclaw] Attachment added: \(name) (\(ThreadMessage.formatSize(size)))")
        }
        if !urls.isEmpty {
            showThread = true
        }
    }

    // MARK: - Clarification Response (now via thread)

    func respondToClarification(_ answer: String) {
        pendingClarification = nil
        threadMessages.append(.userMessage(text: answer))
        sendToHaiku()
    }

    func dismissClarification() {
        pendingClarification = nil
        statusLine = "Listening..."
    }

    func dismissError() {
        deductionError = nil
        statusLine = "Listening..."
    }

    // MARK: - Approval -> Execution

    func approveSuggestion() {
        guard let suggestion = currentSuggestion, let project = selectedProject else { return }

        isExecuting = true
        executionOutput = ""
        statusLine = "Executing..."

        // Update thread with the task info
        if let thread = currentThread {
            sessionStore.updateThread(id: thread.id, title: suggestion.title, taskTitle: suggestion.title)
            // Keep currentThread in sync
            if let updated = sessionStore.threads.first(where: { $0.id == thread.id }) {
                currentThread = updated
            }
        }

        executionTask = Task {
            do {
                for try await chunk in claudeCodeRunner.execute(suggestion: suggestion, project: project, sessionId: currentSessionId) {
                    guard !Task.isCancelled else { break }
                    self.executionOutput += chunk
                }
                if !Task.isCancelled {
                    self.threadMessages.append(.execution(output: self.executionOutput))
                }
            } catch {
                if !Task.isCancelled {
                    let errMsg = error.localizedDescription
                    self.executionOutput += "\n[Error: \(errMsg)]"
                    self.threadMessages.append(.error(message: errMsg))
                }
            }
            self.isExecuting = false
            self.executionTask = nil
            self.statusLine = "Done"
        }
    }

    // MARK: - Direct Execute (skip deduction, go straight to Claude Code)

    /// Send a message + accumulated context directly to Claude Code for execution
    func directExecuteMessage(_ text: String) {
        if !text.isEmpty {
            threadMessages.append(.userMessage(text: text))
        }
        directExecute()
    }

    // MARK: - Skill-Based Mode Routing

    /// Maps each request mode to a Claude Code skill name (in ~/.claude/skills/)
    private func skillName(for mode: RequestMode) -> String {
        switch mode {
        case .question:    return "autoclaw-question"
        case .task:        return "autoclaw-task"
        case .addToTasks:  return "autoclaw-add-to-tasks"
        case .analyze:     return "autoclaw-analyze"
        case .learn:       return "autoclaw-task"  // Learn uses task skill for execution
        }
    }

    /// Build prompt from thread context and send directly to Claude Code.
    /// Invokes the appropriate skill via `/skill-name` prefix.
    func directExecute() {
        guard let project = selectedProject else { return }

        // Gather context from thread
        var clipboardEntries: [ClipboardEntry] = []
        var userMessages: [String] = []
        var attachmentPaths: [String] = []

        for msg in threadMessages {
            switch msg {
            case .clipboard(_, let content, let app, let window, _):
                clipboardEntries.append(ClipboardEntry(content: content, app: app, window: window))
            case .userMessage(_, let text, _):
                userMessages.append(text)
            case .attachment(_, let path, _, _, _):
                attachmentPaths.append(path)
            default:
                break
            }
        }

        guard !clipboardEntries.isEmpty || !userMessages.isEmpty || !attachmentPaths.isEmpty else { return }

        // Build context sections (skill handles the behavior rules)
        var contextParts: [String] = []

        if !clipboardEntries.isEmpty {
            contextParts.append("## Clipboard Context")
            for (i, entry) in clipboardEntries.enumerated() {
                contextParts.append("### Capture \(i + 1) (from \(entry.app) — \(entry.window))\n```\n\(entry.content)\n```")
            }
        }

        if !userMessages.isEmpty {
            contextParts.append("## User Input")
            for msg in userMessages {
                contextParts.append("- \"\(msg)\"")
            }
        }

        if !attachmentPaths.isEmpty {
            contextParts.append("## Attached Files")
            for path in attachmentPaths {
                contextParts.append("- \(path)")
            }
        }

        // Attach recent key frames so Sonnet can see what the user is doing
        let keyFramePaths = keyFrameAnalyzer?.recentFramePaths(limit: 3) ?? []
        if !keyFramePaths.isEmpty {
            contextParts.append("## Recent Screen Context (key frames from the user's session)")
            for path in keyFramePaths {
                contextParts.append("- \(path)")
            }
        }

        let context = contextParts.joined(separator: "\n\n")

        // Invoke the skill: /autoclaw-question <context>
        let skill = skillName(for: requestMode)
        let prompt = "/\(skill) \(context)"

        isExecuting = true
        executionOutput = ""
        statusLine = "Executing (\(selectedModel.displayName))..."

        // Update thread title from first user message
        let title = userMessages.last ?? "Direct execution"
        if let thread = currentThread {
            sessionStore.updateThread(id: thread.id, title: String(title.prefix(40)), taskTitle: title)
            if let updated = sessionStore.threads.first(where: { $0.id == thread.id }) {
                currentThread = updated
            }
        }

        print("[Autoclaw] Direct execute with \(selectedModel.displayName): \(title.prefix(60))")

        executionTask = Task {
            do {
                for try await chunk in claudeCodeRunner.executeDirect(
                    prompt: prompt,
                    project: project,
                    model: selectedModel,
                    sessionId: currentSessionId
                ) {
                    guard !Task.isCancelled else { break }
                    self.executionOutput += chunk
                }
                if !Task.isCancelled {
                    self.threadMessages.append(.execution(output: self.executionOutput))
                }
            } catch {
                if !Task.isCancelled {
                    let errMsg = error.localizedDescription
                    self.executionOutput += "\n[Error: \(errMsg)]"
                    self.threadMessages.append(.error(message: errMsg))
                }
            }
            self.isExecuting = false
            self.executionTask = nil
            self.statusLine = "Done"
        }
    }

    func dismissSuggestion() {
        currentSuggestion = nil
        statusLine = "Listening..."
    }

    func dismissThread() {
        showThread = false
    }

    // MARK: - Learn Mode

    func startLearnRecording() {
        guard let project = selectedProject else {
            needsProjectSelection = true
            statusLine = "Select a project to record"
            return
        }

        // Start a session if not already active
        if !sessionActive {
            startSession()
        }

        workflowRecorder.startRecording(projectId: project.id)
        isLearnRecording = true
        browserEventBuffer = []
        frictionDetector.isSuppressed = true  // Don't suggest workflows while learning a new one
        statusLine = "Recording workflow..."
        showThread = true

        // Tell Chrome extension to start capturing DOM events
        if browserBridge.isConnected {
            browserBridge.startRecording()
            statusLine = "Recording workflow + browser..."
        }

        // Observe recorder events to forward clicks to the thread
        workflowRecorder.$events
            .removeDuplicates { $0.count == $1.count }
            .dropFirst()
            .sink { [weak self] events in
                guard let self = self, self.isLearnRecording else { return }
                if let lastEvent = events.last, lastEvent.type == .click {
                    self.threadMessages.append(.learnEvent(event: lastEvent))
                }
            }
            .store(in: &cancellables)

        print("[Autoclaw] Learn recording started (browser bridge: \(browserBridge.isConnected ? "connected" : "not connected"))")
    }

    func stopLearnRecording() {
        guard isLearnRecording else { return }

        // Stop Chrome extension recording
        browserBridge.stopRecording()

        guard let recording = workflowRecorder.stopRecording() else {
            isLearnRecording = false
            frictionDetector.isSuppressed = false
            return
        }

        isLearnRecording = false
        frictionDetector.isSuppressed = false
        currentRecording = recording
        isExtractingSteps = true
        statusLine = "Extracting steps..."

        // Suggest a name from the first event descriptions
        let firstEvents = recording.events.prefix(3).map(\.description)
        workflowNameDraft = firstEvents.first ?? "Untitled workflow"

        // Gather key frame screenshots captured during the recording
        let screenshotPaths = keyFrameAnalyzer?.recentFramePaths(limit: 8) ?? []

        // Build capability summary so extraction maps steps to real MCP tools
        let capSummary = buildCapabilitySummary()

        // Gather DOM events from Chrome extension (if connected)
        let domEvents = browserEventBuffer

        // Extract steps using AI — with screenshots, capabilities, and DOM events
        Task { @MainActor in
            do {
                let steps = try await WorkflowExtractor.extractSteps(
                    from: recording,
                    model: self.selectedModel,
                    savedWorkflows: self.workflowStore.workflows,
                    screenshotPaths: screenshotPaths,
                    capabilities: capSummary,
                    domEvents: domEvents
                )
                self.extractedSteps = steps
                self.statusLine = "\(steps.count) steps extracted"
                print("[Autoclaw] Extracted \(steps.count) workflow steps (with \(screenshotPaths.count) screenshots, \(domEvents.count) DOM events)")
            } catch {
                print("[Autoclaw] Step extraction failed: \(error)")
                self.extractedSteps = []
                self.statusLine = "Extraction failed"
                self.threadMessages.append(.error(message: "Step extraction failed: \(error.localizedDescription)"))
            }
            self.isExtractingSteps = false
            // Clear DOM event buffer after extraction
            self.browserEventBuffer = []
        }
    }

    func saveWorkflow(name: String) {
        guard let recording = currentRecording else { return }

        let workflow = SavedWorkflow(
            name: name.isEmpty ? "Untitled workflow" : name,
            projectId: recording.projectId,
            steps: extractedSteps
        )

        // Save to store
        workflowStore.save(workflow: workflow)

        // Generate skill file
        do {
            try WorkflowSkillTemplate.generateSkillFile(for: workflow, events: recording.events)
        } catch {
            print("[Autoclaw] Failed to write skill file: \(error)")
        }

        // Add confirmation to thread
        threadMessages.append(.workflowSaved(workflow: workflow))

        // Reset learn state
        currentRecording = nil
        extractedSteps = []
        workflowNameDraft = ""
        statusLine = "Workflow saved: \(workflow.name)"
        print("[Autoclaw] Workflow saved: \(workflow.name) (\(workflow.steps.count) steps)")
    }

    func discardLearnRecording() {
        workflowRecorder.discardRecording()
        isLearnRecording = false
        currentRecording = nil
        extractedSteps = []
        workflowNameDraft = ""
        browserEventBuffer = []
        statusLine = "Recording discarded"
    }

    /// Build a human-readable summary of installed capabilities for extraction prompt context
    private func buildCapabilitySummary() -> String {
        let caps = capabilityMap.capabilities
        guard !caps.isEmpty else { return "" }

        var lines: [String] = []
        // Group by provider
        var byProvider: [String: [CapabilityMap.Capability]] = [:]
        for cap in caps where cap.isInstalled {
            byProvider[cap.provider, default: []].append(cap)
        }

        for (provider, providerCaps) in byProvider.sorted(by: { $0.key < $1.key }) {
            let actions = providerCaps.flatMap(\.actions).unique()
            let apps = providerCaps.map(\.sourceApp).unique()
            lines.append("- **\(provider)**: \(providerCaps.map(\.name).joined(separator: ", ")) — apps: \(apps.joined(separator: ", ")) — actions: \(actions.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    func executeWorkflow(_ workflow: SavedWorkflow) {
        guard let project = selectedProject else { return }

        // Start a session if needed
        if !sessionActive {
            startSession()
        }

        let skillName = workflow.skillFileName
        let prompt = "/\(skillName) Execute this learned workflow now."

        isExecuting = true
        executionOutput = ""
        statusLine = "Running: \(workflow.name)..."

        // Update thread
        if let thread = currentThread {
            sessionStore.updateThread(id: thread.id, title: "Workflow: \(workflow.name)", taskTitle: workflow.name)
            if let updated = sessionStore.threads.first(where: { $0.id == thread.id }) {
                currentThread = updated
            }
        }

        // Mark as run
        workflowStore.markRun(id: workflow.id)

        Task {
            do {
                for try await chunk in claudeCodeRunner.executeDirect(
                    prompt: prompt,
                    project: project,
                    model: selectedModel,
                    sessionId: currentSessionId
                ) {
                    self.executionOutput += chunk
                }
                self.threadMessages.append(.execution(output: self.executionOutput))
            } catch {
                let errMsg = error.localizedDescription
                self.executionOutput += "\n[Error: \(errMsg)]"
                self.threadMessages.append(.error(message: errMsg))
            }
            self.isExecuting = false
            self.statusLine = "Done"
        }
    }

    /// Forward app/clipboard changes to recorder when in learn mode
    func forwardToRecorderIfNeeded(app: String, window: String) {
        guard isLearnRecording else { return }
        let url = activeWindowService.browserURL
        workflowRecorder.recordAppSwitch(app: app, window: window, url: url)

        // Add event to thread for live display
        if let lastEvent = workflowRecorder.events.last {
            threadMessages.append(.learnEvent(event: lastEvent))
        }
    }

    func forwardClipboardToRecorderIfNeeded(content: String, app: String, window: String) {
        guard isLearnRecording else { return }
        workflowRecorder.recordClipboardChange(content: content, app: app, window: window)

        if let lastEvent = workflowRecorder.events.last {
            threadMessages.append(.learnEvent(event: lastEvent))
        }
    }

    // MARK: - ARIA Friction Actions

    func dismissFriction() {
        activeFriction = nil
        frictionDetector.dismissFriction()
    }

    /// User accepted a friction offer — execute the suggested automation
    func acceptFrictionOffer(_ signal: FrictionDetector.FrictionSignal) {
        guard let project = selectedProject else { return }
        activeFriction = nil
        frictionDetector.dismissFriction()

        // Build a prompt that uses the matched capability
        let capName = signal.capability?.name ?? "available tools"
        let prompt = """
        The user was manually \(signal.description). \
        Use \(capName) to automate this. \
        Apps involved: \(signal.involvedApps.joined(separator: ", ")).
        """

        threadMessages.append(.userMessage(text: "Automate: \(signal.description)"))

        isExecuting = true
        executionOutput = ""
        statusLine = "Automating..."

        executionTask = Task {
            do {
                for try await chunk in claudeCodeRunner.executeDirect(
                    prompt: prompt,
                    project: project,
                    model: selectedModel,
                    sessionId: currentSessionId
                ) {
                    guard !Task.isCancelled else { break }
                    self.executionOutput += chunk
                }
                if !Task.isCancelled {
                    self.threadMessages.append(.execution(output: self.executionOutput))
                }
            } catch {
                if !Task.isCancelled {
                    let errMsg = error.localizedDescription
                    self.threadMessages.append(.error(message: errMsg))
                }
            }
            self.isExecuting = false
            self.executionTask = nil
            self.statusLine = "Done"
        }
    }

    /// User wants to discover capabilities for a friction pattern
    func discoverCapability(for signal: FrictionDetector.FrictionSignal) {
        guard signal.involvedApps.count >= 2 else { return }
        activeFriction = nil
        frictionDetector.dismissFriction()
        statusLine = "Searching for integrations..."

        Task {
            let result = await capabilityDiscovery.discover(
                sourceApp: signal.involvedApps[0],
                targetApp: signal.involvedApps[1],
                frictionDescription: signal.description
            )

            if let result = result, !result.findings.isEmpty {
                let names = result.findings.map(\.name).joined(separator: ", ")
                self.threadMessages.append(.userMessage(text: "Found integrations: \(names)"))
                self.statusLine = "Found \(result.findings.count) integrations"
            } else {
                self.threadMessages.append(.error(message: "No integrations found for \(signal.involvedApps.joined(separator: " → "))"))
                self.statusLine = "No integrations found"
            }
        }
    }

    // MARK: - Voice Mode

    func toggleVoice() {
        if !sessionActive {
            startSession()
        }

        if voiceService.isListening {
            voiceService.stopListening()
            statusLine = "Voice off"
        } else {
            voiceService.requestPermissions { [weak self] granted in
                guard granted else {
                    self?.statusLine = "Mic permission denied"
                    return
                }
                self?.voiceService.startListening()
                self?.statusLine = "Listening..."
                self?.showThread = true
            }
        }
    }
}

// MARK: - Array Helpers

extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
