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
    @Published var selectedProject: Project?
    @Published var needsProjectSelection = false
    @Published var currentSessionId: String?
    @Published var sessionScreenshotPath: String?
    @Published var currentThread: SessionThread?

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
        statusLine = "Session started"

        // Always create thread — attach project now or later
        if let sid = currentSessionId {
            let projectId = selectedProject?.id ?? UUID()
            currentThread = sessionStore.createThread(sessionId: sid, projectId: projectId)
        }

        print("[Autoclaw] Session started: \(currentSessionId ?? "?")")
        captureSessionScreenshot()
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
        statusLine = "Resumed: \(thread.title)"

        // Set the project to match the thread's project
        if let project = projectStore.projects.first(where: { $0.id == thread.projectId }) {
            selectedProject = project
        }

        sessionStore.updateThread(id: thread.id)
        print("[Autoclaw] Session resumed: \(currentSessionId ?? "?") — \(thread.title)")
        captureSessionScreenshot()
    }

    func endSession() {
        let ended = currentSessionId
        sessionActive = false
        currentSuggestion = nil
        isDeducing = false
        isExecuting = false
        executionOutput = ""
        deductionError = nil
        pendingClarification = nil
        needsProjectSelection = false
        currentSessionId = nil
        currentThread = nil
        statusLine = "Ready"

        if let path = sessionScreenshotPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        sessionScreenshotPath = nil

        print("[Autoclaw] Session ended: \(ended ?? "?")")
    }

    // MARK: - Screenshot Capture

    private func captureSessionScreenshot() {
        statusLine = "Capturing screen..."

        // Use nominalResolution (1x) instead of bestResolution (retina) to keep image small
        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else {
            print("[Autoclaw] Failed to capture session screenshot")
            statusLine = "Listening..."
            return
        }

        // Resize to max 1024px wide for API size limits
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
        ) else {
            print("[Autoclaw] Failed to create bitmap for screenshot resize")
            statusLine = "Listening..."
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        nsImage.draw(in: NSRect(x: 0, y: 0, width: dstW, height: dstH))
        NSGraphicsContext.restoreGraphicsState()

        // Use JPEG at 60% quality — much smaller than PNG for photos/screenshots
        guard let jpegData = resized.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
            print("[Autoclaw] Failed to encode screenshot as JPEG")
            statusLine = "Listening..."
            return
        }

        let tmpDir = NSTemporaryDirectory()
        let filename = "autoclaw_session_\(currentSessionId ?? "unknown").jpg"
        let path = (tmpDir as NSString).appendingPathComponent(filename)

        do {
            try jpegData.write(to: URL(fileURLWithPath: path))
            sessionScreenshotPath = path
            let sizeKB = jpegData.count / 1024
            print("[Autoclaw] Session screenshot saved: \(path) (\(sizeKB)KB, \(dstW)x\(dstH))")
            statusLine = "Listening..."
        } catch {
            print("[Autoclaw] Failed to write screenshot: \(error)")
            statusLine = "Listening..."
        }
    }

    // MARK: - Clipboard -> Deduction

    private func handleClipboardChange(_ content: String) {
        guard sessionActive, !isDeducing, !isExecuting else { return }

        lastClipboard = content
        clipboardCapturedApp = activeApp
        clipboardCapturedWindow = activeWindowTitle
        statusLine = "Clipboard captured"

        if selectedProject == nil {
            needsProjectSelection = true
            statusLine = "Select a project"
        } else {
            needsProjectSelection = false
            deduceTask()
        }
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

        if !lastClipboard.isEmpty {
            deduceTask()
        }
    }

    func deduceTask() {
        guard let project = selectedProject else { return }
        guard !lastClipboard.isEmpty else { return }

        isDeducing = true
        currentSuggestion = nil
        deductionError = nil
        pendingClarification = nil
        statusLine = "Analyzing..."

        let context = TaskContext(
            clipboard: lastClipboard,
            activeApp: clipboardCapturedApp,
            windowTitle: clipboardCapturedWindow,
            project: project,
            screenshotPath: sessionScreenshotPath
        )

        Task { @MainActor in
            do {
                let suggestion = try await taskDeductionService.deduce(context: context)

                if suggestion.needsClarification {
                    print("[Autoclaw] Setting pendingClarification: \(suggestion.clarification?.question ?? "?")")
                    self.pendingClarification = suggestion.clarification
                    self.currentSuggestion = nil
                    self.statusLine = "Needs info"
                } else {
                    print("[Autoclaw] Setting currentSuggestion: \(suggestion.title)")
                    self.currentSuggestion = suggestion
                    self.pendingClarification = nil
                    self.statusLine = suggestion.title
                }
            } catch {
                print("[Autoclaw] Deduction error: \(error.localizedDescription)")
                self.deductionError = error.localizedDescription
                self.currentSuggestion = nil
                self.pendingClarification = nil
                self.statusLine = "Deduction failed"
            }
            self.isDeducing = false
        }
    }

    // MARK: - Clarification Response

    func respondToClarification(_ answer: String) {
        guard let project = selectedProject else { return }
        pendingClarification = nil

        let augmented = lastClipboard + "\n\n[User clarification: \(answer)]"
        lastClipboard = augmented

        isDeducing = true
        currentSuggestion = nil
        deductionError = nil
        statusLine = "Re-analyzing..."

        let context = TaskContext(
            clipboard: augmented,
            activeApp: clipboardCapturedApp,
            windowTitle: clipboardCapturedWindow,
            project: project,
            screenshotPath: sessionScreenshotPath
        )

        Task {
            do {
                let suggestion = try await taskDeductionService.deduce(context: context)
                if suggestion.needsClarification {
                    self.pendingClarification = suggestion.clarification
                } else {
                    self.currentSuggestion = suggestion
                }
            } catch {
                self.deductionError = error.localizedDescription
            }
            self.isDeducing = false
        }
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
            } catch {
                self.executionOutput += "\n[Error: \(error.localizedDescription)]"
            }
            self.isExecuting = false
        }
    }

    func dismissSuggestion() {
        currentSuggestion = nil
        statusLine = "Listening..."
    }
}
