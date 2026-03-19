import Foundation

/// The kind of response Haiku determined — drives which CTA is shown
enum TaskKind: String {
    case execute    // Requires Claude Code to run (code changes, shell, etc.)
    case draft      // A piece of text to copy and use (email reply, doc, message)
    case answer     // An informational answer / lookup / explanation to copy
    case clarification  // Haiku needs more info before it can act
}

struct TaskSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let draft: String
    let skills: [String]          // Skill chain — ordered list of skills/tools
    let completionPlan: String?
    let confidence: Double
    let kind: TaskKind            // Determines which UI / CTA to show
    let clarification: Clarification?  // Non-nil when kind == .clarification

    /// Convenience for single-skill backward compat
    var skill: String? { skills.first }

    /// Whether this suggestion is actually a question, not a task
    var needsClarification: Bool { clarification != nil }
}

struct Clarification {
    let question: String
    let options: [String]?         // Optional multiple-choice
    let context: String?           // Why it's asking
}

// MARK: - Thread Message

/// A single entry in the session's chat thread
enum ThreadMessage: Identifiable {
    case clipboard(id: UUID = UUID(), content: String, app: String, window: String, date: Date = Date())
    case screenshot(id: UUID = UUID(), path: String, date: Date = Date())
    case userMessage(id: UUID = UUID(), text: String, date: Date = Date())
    case haiku(id: UUID = UUID(), suggestion: TaskSuggestion, date: Date = Date())
    case execution(id: UUID = UUID(), output: String, date: Date = Date())
    case error(id: UUID = UUID(), message: String, date: Date = Date())
    case context(id: UUID = UUID(), app: String, window: String, date: Date = Date())
    case attachment(id: UUID = UUID(), path: String, name: String, size: Int64, date: Date = Date())
    case learnEvent(id: UUID = UUID(), event: WorkflowEvent, date: Date = Date())
    case workflowSaved(id: UUID = UUID(), workflow: SavedWorkflow, date: Date = Date())
    case frictionOffer(id: UUID = UUID(), signal: FrictionDetector.FrictionSignal, date: Date = Date())

    var id: UUID {
        switch self {
        case .clipboard(let id, _, _, _, _): return id
        case .screenshot(let id, _, _): return id
        case .userMessage(let id, _, _): return id
        case .haiku(let id, _, _): return id
        case .execution(let id, _, _): return id
        case .error(let id, _, _): return id
        case .context(let id, _, _, _): return id
        case .attachment(let id, _, _, _, _): return id
        case .learnEvent(let id, _, _): return id
        case .workflowSaved(let id, _, _): return id
        case .frictionOffer(let id, _, _): return id
        }
    }

    var date: Date {
        switch self {
        case .clipboard(_, _, _, _, let d): return d
        case .screenshot(_, _, let d): return d
        case .userMessage(_, _, let d): return d
        case .haiku(_, _, let d): return d
        case .execution(_, _, let d): return d
        case .error(_, _, let d): return d
        case .context(_, _, _, let d): return d
        case .attachment(_, _, _, _, let d): return d
        case .learnEvent(_, _, let d): return d
        case .workflowSaved(_, _, let d): return d
        case .frictionOffer(_, _, let d): return d
        }
    }

    /// File extension icon mapping
    static func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "xlsx", "xls", "csv": return "tablecells"
        case "docx", "doc", "rtf": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "aac", "m4a": return "waveform"
        case "zip", "tar", "gz", "rar": return "archivebox"
        case "swift", "py", "js", "ts", "rb", "go", "rs": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "xml", "plist": return "curlybraces"
        case "txt", "md": return "doc.plaintext"
        default: return "doc"
        }
    }

    /// Human-readable file size
    static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Task Context (refactored for thread)

struct ClipboardEntry {
    let content: String
    let app: String
    let window: String
}

struct TaskContext {
    let clipboardEntries: [ClipboardEntry]
    let userMessages: [String]
    let screenshotPaths: [String]
    let attachmentPaths: [String]
    let project: Project
}
