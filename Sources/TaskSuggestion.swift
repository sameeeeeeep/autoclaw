import Foundation

struct TaskSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let draft: String
    let skills: [String]          // Skill chain — ordered list of skills/tools
    let completionPlan: String?
    let confidence: Double
    let clarification: Clarification?  // Non-nil when Haiku needs more info

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

struct TaskContext {
    let clipboard: String
    let activeApp: String
    let windowTitle: String
    let project: Project
    let screenshotPath: String?    // Path to session screenshot, if available
}
