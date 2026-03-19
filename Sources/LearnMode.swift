import Foundation

// MARK: - Workflow Event Types

enum WorkflowEventType: String, Codable {
    case appSwitch      // User switched to a different app
    case clipboard      // User copied something
    case screenshot     // Periodic or trigger-based screenshot
    case click          // Mouse click with OCR context of what was clicked
    case idle           // Gap in activity (>30s no events)
}

// MARK: - Workflow Event

struct WorkflowEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: WorkflowEventType
    let app: String
    let window: String
    let description: String
    let data: String?            // clipboard content, URL, etc.
    let screenshotPath: String?  // path to screenshot if captured
    let ocrContext: String?      // OCR text near cursor + ambient screen text

    /// Elapsed seconds from recording start (set by recorder)
    var elapsed: TimeInterval = 0

    init(
        type: WorkflowEventType,
        app: String,
        window: String,
        description: String,
        data: String? = nil,
        screenshotPath: String? = nil,
        ocrContext: String? = nil,
        elapsed: TimeInterval = 0
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.app = app
        self.window = window
        self.description = description
        self.data = data
        self.screenshotPath = screenshotPath
        self.ocrContext = ocrContext
        self.elapsed = elapsed
    }

    /// Format elapsed as "M:SS"
    var elapsedFormatted: String {
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Workflow Recording (in-progress capture)

struct WorkflowRecording: Identifiable, Codable {
    let id: UUID
    let projectId: UUID
    var events: [WorkflowEvent]
    let startedAt: Date
    var stoppedAt: Date?

    var duration: TimeInterval {
        (stoppedAt ?? Date()).timeIntervalSince(startedAt)
    }

    init(projectId: UUID) {
        self.id = UUID()
        self.projectId = projectId
        self.events = []
        self.startedAt = Date()
    }
}

// MARK: - Workflow Step (extracted by AI)

struct WorkflowStep: Identifiable, Codable {
    let id: UUID
    let index: Int
    let description: String
    let tool: String             // e.g. "notion_read", "clipboard", "chrome", "Claude"
    let estimatedSeconds: Int?

    init(index: Int, description: String, tool: String, estimatedSeconds: Int? = nil) {
        self.id = UUID()
        self.index = index
        self.description = description
        self.tool = tool
        self.estimatedSeconds = estimatedSeconds
    }

    var estimatedTimeFormatted: String? {
        guard let s = estimatedSeconds else { return nil }
        if s < 60 { return "~\(s)s" }
        let m = s / 60
        let rem = s % 60
        return rem > 0 ? "~\(m)m \(rem)s" : "~\(m)m"
    }
}

// MARK: - Saved Workflow

struct SavedWorkflow: Identifiable, Codable {
    let id: UUID
    var name: String
    let projectId: UUID
    let steps: [WorkflowStep]
    let skillFileName: String    // e.g. "autoclaw-workflow-abc123"
    let createdAt: Date
    var lastRunAt: Date?
    var runCount: Int

    init(name: String, projectId: UUID, steps: [WorkflowStep]) {
        self.id = UUID()
        self.name = name
        self.projectId = projectId
        self.steps = steps
        self.skillFileName = "autoclaw-workflow-\(UUID().uuidString.prefix(8).lowercased())"
        self.createdAt = Date()
        self.lastRunAt = nil
        self.runCount = 0
    }

    var totalEstimatedSeconds: Int {
        steps.compactMap(\.estimatedSeconds).reduce(0, +)
    }

    var totalEstimatedFormatted: String {
        let s = totalEstimatedSeconds
        if s == 0 { return "unknown" }
        if s < 60 { return "~\(s)s" }
        let m = s / 60
        return "~\(m) min"
    }
}

// MARK: - Workflow Store

@MainActor
final class WorkflowStore: ObservableObject {
    @Published var workflows: [SavedWorkflow] = []

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Autoclaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("workflows.json")
        load()
    }

    func workflows(for projectId: UUID) -> [SavedWorkflow] {
        workflows.filter { $0.projectId == projectId }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(workflow: SavedWorkflow) {
        workflows.append(workflow)
        persist()
    }

    func markRun(id: UUID) {
        guard let idx = workflows.firstIndex(where: { $0.id == id }) else { return }
        workflows[idx].lastRunAt = Date()
        workflows[idx].runCount += 1
        persist()
    }

    func rename(id: UUID, name: String) {
        guard let idx = workflows.firstIndex(where: { $0.id == id }) else { return }
        workflows[idx].name = name
        persist()
    }

    func remove(id: UUID) {
        workflows.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([SavedWorkflow].self, from: data) else {
            return
        }
        workflows = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(workflows) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
