import Foundation

/// Extracts structured workflow steps from a raw recording using Claude.
/// Two-phase: scene understanding (Haiku on screenshots), then step extraction.
struct WorkflowExtractor {

    /// Extract logical workflow steps from a raw recording
    static func extractSteps(
        from recording: WorkflowRecording,
        using runner: ClaudeCodeRunner,
        model: ClaudeModel = .haiku
    ) async throws -> [WorkflowStep] {

        // Build the event timeline as a readable prompt
        let timeline = buildTimeline(from: recording)

        let prompt = """
        You are analyzing a recorded user workflow to extract the logical steps.

        ## Recorded Event Timeline
        \(timeline)

        ## Instructions
        Extract the logical workflow steps (not raw events) from this recording.
        Merge related events into single logical steps.
        For each step, identify the most likely tool/service needed to automate it.

        Common tools: clipboard, chrome, notion_read, notion_write, google_sheets, \
        gmail, slack, linkedin_post, job_boards, file_system, Claude, search

        Respond ONLY with a JSON array. No markdown, no explanation.
        Example:
        [
          {"index": 1, "description": "Read job description from Notion", "tool": "notion_read", "estimated_seconds": 5},
          {"index": 2, "description": "Format content for job boards", "tool": "Claude", "estimated_seconds": 10}
        ]
        """

        // Use ClaudeCodeRunner to get the extraction
        var output = ""
        for try await chunk in runner.executeDirect(
            prompt: prompt,
            project: Project(id: recording.projectId, name: "workflow-extract", path: NSTemporaryDirectory()),
            model: model,
            sessionId: nil,
            singleShot: true
        ) {
            output += chunk
        }

        return parseSteps(from: output)
    }

    // MARK: - Timeline Builder

    private static func buildTimeline(from recording: WorkflowRecording) -> String {
        var lines: [String] = []
        lines.append("Duration: \(Int(recording.duration))s")
        lines.append("Events: \(recording.events.count)")
        lines.append("")

        for event in recording.events {
            let time = event.elapsedFormatted
            let type = event.type.rawValue.uppercased()
            var line = "[\(time)] \(type) — \(event.description)"

            if let data = event.data, !data.isEmpty {
                let preview = String(data.prefix(200))
                line += "\n    Content: \"\(preview)\""
            }

            if event.screenshotPath != nil {
                line += " [screenshot captured]"
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Parser

    private static func parseSteps(from output: String) -> [WorkflowStep] {
        // Try to find JSON array in the output
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct parse first
        if let steps = tryParseJSON(trimmed) { return steps }

        // Try to extract JSON from markdown code block
        if let range = trimmed.range(of: "\\[\\s*\\{", options: .regularExpression),
           let endRange = trimmed.range(of: "\\}\\s*\\]", options: .regularExpression, range: range.lowerBound..<trimmed.endIndex) {
            let jsonStr = String(trimmed[range.lowerBound...endRange.upperBound])
            if let steps = tryParseJSON(jsonStr) { return steps }
        }

        print("[WorkflowExtractor] Failed to parse steps from output: \(trimmed.prefix(200))")
        return []
    }

    private static func tryParseJSON(_ json: String) -> [WorkflowStep]? {
        guard let data = json.data(using: .utf8) else { return nil }

        struct RawStep: Decodable {
            let index: Int
            let description: String
            let tool: String
            let estimated_seconds: Int?
        }

        guard let rawSteps = try? JSONDecoder().decode([RawStep].self, from: data) else { return nil }

        return rawSteps.map { raw in
            WorkflowStep(
                index: raw.index,
                description: raw.description,
                tool: raw.tool,
                estimatedSeconds: raw.estimated_seconds
            )
        }
    }
}
