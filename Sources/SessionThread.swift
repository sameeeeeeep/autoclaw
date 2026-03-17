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

@MainActor
final class SessionStore: ObservableObject {
    @Published var threads: [SessionThread] = []

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Autoclaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("sessions.json")
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
        save()
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
