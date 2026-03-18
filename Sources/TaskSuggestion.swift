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

    var id: UUID {
        switch self {
        case .clipboard(let id, _, _, _, _): return id
        case .screenshot(let id, _, _): return id
        case .userMessage(let id, _, _): return id
        case .haiku(let id, _, _): return id
        case .execution(let id, _, _): return id
        case .error(let id, _, _): return id
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
        }
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
    let project: Project
}
