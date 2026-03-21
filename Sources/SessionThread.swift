import Foundation

struct SessionThread: Identifiable, Codable, Hashable {
    let id: UUID               // same as the sessionId passed to --resume
    var projectId: UUID
    var title: String           // auto-generated from first task, editable
    let startedAt: Date
    var lastActiveAt: Date
    var taskCount: Int
    var lastTaskTitle: String?

    init(sessionId: String, projectId: UUID) {
        self.id = UUID(uuidString: sessionId) ?? UUID()
        self.projectId = projectId
        self.title = "New session"
        self.startedAt = Date()
        self.lastActiveAt = Date()
        self.taskCount = 0
        self.lastTaskTitle = nil
    }
}

/// Persistable thread message — simplified version of ThreadMessage for disk storage.
/// Complex types (TaskSuggestion, FrictionSignal) are stored as their text representation.
struct PersistedMessage: Codable, Identifiable {
    let id: UUID
    let date: Date
    let type: MessageType
    let text: String          // primary content
    let secondary: String?    // app name, window title, etc.
    let tertiary: String?     // extra context

    enum MessageType: String, Codable {
        case clipboard, screenshot, userMessage, execution, error
        case context, attachment, learnEvent, workflowSaved, frictionOffer, haiku
    }

    /// Convert a ThreadMessage to its persistable form
    static func from(_ msg: ThreadMessage) -> PersistedMessage {
        switch msg {
        case .clipboard(let id, let content, let app, let window, let date):
            return PersistedMessage(id: id, date: date, type: .clipboard, text: content, secondary: app, tertiary: window)
        case .screenshot(let id, let path, let date):
            return PersistedMessage(id: id, date: date, type: .screenshot, text: path, secondary: nil, tertiary: nil)
        case .userMessage(let id, let text, let date):
            return PersistedMessage(id: id, date: date, type: .userMessage, text: text, secondary: nil, tertiary: nil)
        case .haiku(let id, let suggestion, let date):
            return PersistedMessage(id: id, date: date, type: .haiku, text: suggestion.title, secondary: suggestion.draft, tertiary: suggestion.completionPlan)
        case .execution(let id, let output, let date):
            return PersistedMessage(id: id, date: date, type: .execution, text: output, secondary: nil, tertiary: nil)
        case .error(let id, let message, let date):
            return PersistedMessage(id: id, date: date, type: .error, text: message, secondary: nil, tertiary: nil)
        case .context(let id, let app, let window, let date):
            return PersistedMessage(id: id, date: date, type: .context, text: app, secondary: window, tertiary: nil)
        case .attachment(let id, let path, let name, let size, let date):
            return PersistedMessage(id: id, date: date, type: .attachment, text: path, secondary: name, tertiary: "\(size)")
        case .learnEvent(let id, let event, let date):
            return PersistedMessage(id: id, date: date, type: .learnEvent, text: event.description, secondary: event.app, tertiary: nil)
        case .workflowSaved(let id, let workflow, let date):
            return PersistedMessage(id: id, date: date, type: .workflowSaved, text: workflow.name, secondary: "\(workflow.steps.count) steps", tertiary: nil)
        case .frictionOffer(let id, let signal, let date):
            return PersistedMessage(id: id, date: date, type: .frictionOffer, text: signal.description, secondary: signal.suggestion, tertiary: nil)
        }
    }

    /// Convert back to a ThreadMessage for display
    func toThreadMessage() -> ThreadMessage {
        switch type {
        case .clipboard:
            return .clipboard(id: id, content: text, app: secondary ?? "", window: tertiary ?? "", date: date)
        case .screenshot:
            return .screenshot(id: id, path: text, date: date)
        case .userMessage:
            return .userMessage(id: id, text: text, date: date)
        case .haiku:
            let suggestion = TaskSuggestion(title: text, draft: secondary ?? "", skills: [], completionPlan: tertiary, confidence: 1.0, kind: .answer, clarification: nil)
            return .haiku(id: id, suggestion: suggestion, date: date)
        case .execution:
            return .execution(id: id, output: text, date: date)
        case .error:
            return .error(id: id, message: text, date: date)
        case .context:
            return .context(id: id, app: text, window: secondary ?? "", date: date)
        case .attachment:
            return .attachment(id: id, path: text, name: secondary ?? "", size: Int64(tertiary ?? "0") ?? 0, date: date)
        case .learnEvent:
            let event = WorkflowEvent(type: .click, app: secondary ?? "", window: "", description: text)
            return .learnEvent(id: id, event: event, date: date)
        case .workflowSaved:
            let wf = SavedWorkflow(name: text, projectId: UUID(), steps: [])
            return .workflowSaved(id: id, workflow: wf, date: date)
        case .frictionOffer:
            let signal = FrictionDetector.FrictionSignal(timestamp: date, pattern: .crossAppTransfer, involvedApps: [], description: text, capability: nil, suggestion: secondary ?? "", confidence: 0, isActionable: false)
            return .frictionOffer(id: id, signal: signal, date: date)
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var threads: [SessionThread] = []

    private let storageURL: URL
    private let messagesDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Autoclaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("sessions.json")
        messagesDir = dir.appendingPathComponent("messages", isDirectory: true)
        try? FileManager.default.createDirectory(at: messagesDir, withIntermediateDirectories: true)
        load()
    }

    func threads(for projectId: UUID) -> [SessionThread] {
        threads.filter { $0.projectId == projectId }.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    func createThread(sessionId: String, projectId: UUID) -> SessionThread {
        let thread = SessionThread(sessionId: sessionId, projectId: projectId)
        threads.append(thread)
        save()
        return thread
    }

    func updateThread(id: UUID, title: String? = nil, taskTitle: String? = nil) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        if let title = title {
            threads[idx].title = title
        }
        if let taskTitle = taskTitle {
            threads[idx].lastTaskTitle = taskTitle
            threads[idx].taskCount += 1
        }
        threads[idx].lastActiveAt = Date()
        save()
    }

    func reassignProject(id: UUID, projectId: UUID) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[idx].projectId = projectId
        save()
    }

    func removeThread(id: UUID) {
        threads.removeAll { $0.id == id }
        // Also remove persisted messages
        let msgFile = messagesDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: msgFile)
        save()
    }

    // MARK: - Message Persistence

    /// Save thread messages to disk for a given session
    func saveMessages(_ messages: [ThreadMessage], for sessionId: UUID) {
        let persisted = messages.map { PersistedMessage.from($0) }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        let file = messagesDir.appendingPathComponent("\(sessionId.uuidString).json")
        try? data.write(to: file, options: .atomic)
    }

    /// Load persisted thread messages for a session
    func loadMessages(for sessionId: UUID) -> [ThreadMessage] {
        let file = messagesDir.appendingPathComponent("\(sessionId.uuidString).json")
        guard let data = try? Data(contentsOf: file),
              let persisted = try? JSONDecoder().decode([PersistedMessage].self, from: data) else {
            return []
        }
        return persisted.map { $0.toThreadMessage() }
    }

    /// Check if a session has persisted messages
    func hasMessages(for sessionId: UUID) -> Bool {
        let file = messagesDir.appendingPathComponent("\(sessionId.uuidString).json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([SessionThread].self, from: data) else {
            return
        }
        threads = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(threads) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
