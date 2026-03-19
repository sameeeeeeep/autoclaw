import Foundation

/// Generates Claude Code skill files from saved workflows.
/// Each workflow becomes a skill at ~/.claude/skills/autoclaw-workflow-{id}.md
struct WorkflowSkillTemplate {

    /// Generate and write the skill file for a saved workflow
    static func generateSkillFile(for workflow: SavedWorkflow, events: [WorkflowEvent]) throws {
        let content = buildSkillContent(workflow: workflow, events: events)
        let skillPath = skillFilePath(for: workflow)

        // Ensure ~/.claude/skills/ directory exists
        let dir = (skillPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        try content.write(toFile: skillPath, atomically: true, encoding: .utf8)
        print("[WorkflowSkillTemplate] Skill file written: \(skillPath)")
    }

    /// Remove the skill file for a workflow
    static func removeSkillFile(for workflow: SavedWorkflow) {
        let path = skillFilePath(for: workflow)
        try? FileManager.default.removeItem(atPath: path)
        print("[WorkflowSkillTemplate] Skill file removed: \(path)")
    }

    /// Path to the skill file
    static func skillFilePath(for workflow: SavedWorkflow) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/skills/\(workflow.skillFileName).md"
    }

    // MARK: - Content Builder

    private static func buildSkillContent(workflow: SavedWorkflow, events: [WorkflowEvent]) -> String {
        // Collect unique apps used during recording
        let apps = Set(events.map(\.app)).filter { !$0.isEmpty }.sorted()
        let tools = Set(workflow.steps.map(\.tool)).sorted()

        var md = """
        ---
        description: "\(workflow.name) — learned workflow (\(workflow.steps.count) steps, \(workflow.totalEstimatedFormatted))"
        ---

        # Workflow: \(workflow.name)

        This is an automated workflow learned by observing the user. Execute each step in order using the available MCP tools and system capabilities.

        ## Steps

        """

        for step in workflow.steps {
            let timeStr = step.estimatedTimeFormatted.map { " (\($0))" } ?? ""
            md += "\(step.index). **\(step.description)**\(timeStr)\n"
            md += "   - Tool: `\(step.tool)`\n\n"
        }

        md += """
        ## Context

        - **Apps used during recording:** \(apps.joined(separator: ", "))
        - **Tools involved:** \(tools.joined(separator: ", "))
        - **Total estimated time:** \(workflow.totalEstimatedFormatted)

        ## Recorded Event Summary

        """

        // Add a condensed event summary (not full data, just descriptions)
        let eventSummary = events.prefix(20).map { event in
            "- [\(event.elapsedFormatted)] \(event.description)"
        }
        md += eventSummary.joined(separator: "\n")

        if events.count > 20 {
            md += "\n- ... and \(events.count - 20) more events"
        }

        md += """


        ## Execution Rules

        1. Execute steps in order. Do not skip steps unless explicitly told to.
        2. Use available MCP tools (Chrome control, filesystem, APIs) to automate each step.
        3. For browser-based steps, use the Chrome MCP tools to navigate, click, and fill forms.
        4. For clipboard-based steps, read/write to clipboard as needed.
        5. Ask the user for approval before any destructive or irreversible actions (sending emails, posting publicly, deleting files).
        6. If a step fails, report the error and ask the user how to proceed.
        7. Show progress after each step completes.
        """

        return md
    }
}
