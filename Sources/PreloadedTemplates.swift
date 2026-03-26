import Foundation

// MARK: - Pre-loaded Templates

/// Common workflow templates shipped with the app. These are matched during
/// Analyze mode so the app is useful from day one without learning.
struct PreloadedTemplate {
    let name: String
    let description: String
    let keywords: [String]       // trigger words for matching
    let involvedApps: [String]   // apps this typically involves
    let toolName: String?        // MCP tool or Claude Code skill if known
    let steps: [String]          // human-readable steps
    let category: Category

    enum Category: String {
        case communication  // email, slack, messaging
        case productivity   // tasks, calendar, notes
        case development    // code, git, CI/CD
        case data           // spreadsheets, databases, syncing
        case content        // writing, social, docs
        case research       // search, summarize, extract
    }

    /// Check if a detection description matches this template
    func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        let matchCount = keywords.filter { lower.contains($0) }.count
        // At least 2 keyword matches, or 1 very specific match
        return matchCount >= 2 || keywords.contains(where: { $0.count > 8 && lower.contains($0) })
    }
}

enum PreloadedTemplates {
    static let all: [PreloadedTemplate] = [

        // MARK: - Communication

        PreloadedTemplate(
            name: "Reply to Email",
            description: "Draft a reply to an email based on context",
            keywords: ["email", "reply", "gmail", "mail", "respond", "inbox", "message"],
            involvedApps: ["Gmail", "Mail"],
            toolName: nil,
            steps: ["Read the email thread", "Draft a contextual reply", "Review before sending"],
            category: .communication
        ),

        PreloadedTemplate(
            name: "Respond to Slack Message",
            description: "Draft a response to a Slack message or thread",
            keywords: ["slack", "message", "thread", "reply", "channel", "dm"],
            involvedApps: ["Slack"],
            toolName: nil,
            steps: ["Read the Slack message/thread", "Draft a response", "Post to channel"],
            category: .communication
        ),

        PreloadedTemplate(
            name: "Schedule Meeting",
            description: "Create a calendar event from a conversation",
            keywords: ["meeting", "calendar", "schedule", "invite", "call", "sync"],
            involvedApps: ["Calendar", "Google Calendar"],
            toolName: nil,
            steps: ["Extract meeting details (time, people, agenda)", "Create calendar event", "Send invites"],
            category: .communication
        ),

        // MARK: - Productivity

        PreloadedTemplate(
            name: "Create Task from Context",
            description: "Turn a message, email, or note into a tracked task",
            keywords: ["task", "todo", "create", "add", "clickup", "linear", "jira", "ticket"],
            involvedApps: ["ClickUp", "Linear", "Jira"],
            toolName: "mcp__clickup",
            steps: ["Extract task details from context", "Create task in project management tool", "Set priority and assignee"],
            category: .productivity
        ),

        PreloadedTemplate(
            name: "Summarize Meeting Notes",
            description: "Turn raw meeting notes into structured summary with action items",
            keywords: ["meeting", "notes", "summary", "action items", "minutes", "recap"],
            involvedApps: ["Notion", "Docs", "Notes"],
            toolName: nil,
            steps: ["Read meeting notes/transcript", "Extract key decisions and action items", "Format as structured summary"],
            category: .productivity
        ),

        PreloadedTemplate(
            name: "Update Status/Standup",
            description: "Generate a standup update from recent activity",
            keywords: ["standup", "status", "update", "daily", "progress", "what did"],
            involvedApps: ["Slack", "ClickUp", "Linear"],
            toolName: nil,
            steps: ["Review recent commits and tasks", "Draft standup update", "Post to channel"],
            category: .productivity
        ),

        // MARK: - Development

        PreloadedTemplate(
            name: "Fix Bug from Error",
            description: "Diagnose and fix a bug from an error message or stack trace",
            keywords: ["error", "bug", "fix", "crash", "stack trace", "exception", "failed"],
            involvedApps: ["Terminal", "Xcode", "VS Code"],
            toolName: nil,
            steps: ["Analyze the error/stack trace", "Locate the relevant code", "Implement and test the fix"],
            category: .development
        ),

        PreloadedTemplate(
            name: "Create Pull Request",
            description: "Create a PR with description from current changes",
            keywords: ["pull request", "pr", "commit", "push", "review", "merge"],
            involvedApps: ["Terminal", "GitHub"],
            toolName: nil,
            steps: ["Review staged changes", "Generate PR title and description", "Create PR on GitHub"],
            category: .development
        ),

        PreloadedTemplate(
            name: "Review Code Changes",
            description: "Review a PR or code diff and provide feedback",
            keywords: ["review", "diff", "changes", "code review", "feedback", "approve"],
            involvedApps: ["GitHub", "Terminal"],
            toolName: nil,
            steps: ["Read the diff/PR", "Identify issues and improvements", "Write review comments"],
            category: .development
        ),

        // MARK: - Data

        PreloadedTemplate(
            name: "Sync Data Between Apps",
            description: "Transfer or sync data from one app to another",
            keywords: ["sync", "transfer", "export", "import", "copy", "migrate", "sheets", "notion"],
            involvedApps: ["Sheets", "Notion", "Airtable"],
            toolName: nil,
            steps: ["Read data from source", "Transform/map fields", "Write to destination"],
            category: .data
        ),

        PreloadedTemplate(
            name: "Extract Data from Page",
            description: "Scrape or extract structured data from a webpage",
            keywords: ["extract", "scrape", "data", "table", "webpage", "parse", "csv"],
            involvedApps: ["Chrome", "Safari"],
            toolName: nil,
            steps: ["Read the webpage content", "Extract structured data", "Format as table/CSV"],
            category: .data
        ),

        // MARK: - Content

        PreloadedTemplate(
            name: "Draft Social Post",
            description: "Write a social media post from content or context",
            keywords: ["post", "tweet", "linkedin", "social", "share", "publish", "thread"],
            involvedApps: ["Twitter", "LinkedIn"],
            toolName: nil,
            steps: ["Understand the content/context", "Draft platform-appropriate post", "Review tone and length"],
            category: .content
        ),

        PreloadedTemplate(
            name: "Write Document Section",
            description: "Draft a section of a document based on context",
            keywords: ["write", "draft", "document", "section", "paragraph", "notion", "docs"],
            involvedApps: ["Notion", "Docs", "Word"],
            toolName: nil,
            steps: ["Understand the document context", "Draft the section", "Match existing style and tone"],
            category: .content
        ),

        // MARK: - Research

        PreloadedTemplate(
            name: "Research and Summarize",
            description: "Research a topic and provide a concise summary",
            keywords: ["research", "find", "search", "summarize", "what is", "how to", "explain"],
            involvedApps: ["Chrome", "Safari"],
            toolName: nil,
            steps: ["Search for relevant information", "Read and analyze sources", "Produce concise summary"],
            category: .research
        ),

        PreloadedTemplate(
            name: "Compare Options",
            description: "Compare products, tools, or approaches and recommend",
            keywords: ["compare", "vs", "versus", "which", "best", "recommend", "alternative"],
            involvedApps: ["Chrome", "Safari"],
            toolName: nil,
            steps: ["Gather information on each option", "Compare on key criteria", "Recommend with reasoning"],
            category: .research
        ),
    ]
}
