import SwiftUI
import Combine

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

    // MARK: - Session State
    @Published var sessionActive = false
    @Published var sessionPaused = false
    @Published var selectedProject: Project?
    @Published var needsProjectSelection = false
    @Published var currentSessionId: String?
    @Published var currentThread: SessionThread?

    // MARK: - Thread (the chat thread in the toast)
    @Published var threadMessages: [ThreadMessage] = []
    @Published var showThread = false

    // MARK: - Task Flow
    @Published var currentSuggestion: TaskSuggestion?
    @Published var isDeducing = false
    @Published var isExecuting = false
    @Published var executionOutput = ""
    @Published var deductionError: String?

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

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupBindings()
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

        // Replace existing context message or add new one
        if let idx = threadMessages.lastIndex(where: {
            if case .context = $0 { return true }; return false
        }) {
            threadMessages[idx] = .context(app: app, window: window)
        } else {
            threadMessages.append(.context(app: app, window: window))
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

        // Add initial context chip and show toast immediately
        if !activeApp.isEmpty {
            threadMessages.append(.context(app: activeApp, window: activeWindowTitle))
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

    func endSession() {
        let ended = currentSessionId
        sessionActive = false
        sessionPaused = false
        currentSuggestion = nil
        isDeducing = false
        isExecuting = false
        executionOutput = ""
        deductionError = nil
        pendingClarification = nil
        needsProjectSelection = false
        currentSessionId = nil
        currentThread = nil
        threadMessages = []
        showThread = false
        statusLine = "Ready"

        print("[Autoclaw] Session ended: \(ended ?? "?")")
    }

    // MARK: - Clipboard -> Thread (no longer auto-deduces)

    private func handleClipboardChange(_ content: String) {
        guard sessionActive, !isDeducing, !isExecuting else { return }

        lastClipboard = content
        clipboardCapturedApp = activeApp
        clipboardCapturedWindow = activeWindowTitle

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
                let suggestion = try await taskDeductionService.deduce(context: context)

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

        Task {
            do {
                for try await chunk in claudeCodeRunner.execute(suggestion: suggestion, project: project, sessionId: currentSessionId) {
                    self.executionOutput += chunk
                }
                // Add execution result to thread
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

    func dismissSuggestion() {
        currentSuggestion = nil
        statusLine = "Listening..."
    }

    func dismissThread() {
        showThread = false
    }
}
