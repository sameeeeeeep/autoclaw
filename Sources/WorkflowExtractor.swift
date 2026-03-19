import Foundation

/// Extracts structured workflow steps from a raw recording using Claude.
/// Uses pattern-matching templates to help the AI interpret OCR + click data.
struct WorkflowExtractor {

    /// Extract logical workflow steps from a raw recording
    static func extractSteps(
        from recording: WorkflowRecording,
        using runner: ClaudeCodeRunner,
        model: ClaudeModel = .sonnet,
        savedWorkflows: [SavedWorkflow] = []
    ) async throws -> [WorkflowStep] {

        let timeline = buildTimeline(from: recording)

        // Build similarity hint from saved workflows if available
        let matcher = await WorkflowMatcher()
        let similarityHint = await matcher.buildExtractionHint(
            events: recording.events,
            savedWorkflows: savedWorkflows
        )

        let prompt = """
        You are a workflow analyzer. You receive a timeline of user actions recorded on macOS, \
        including mouse clicks with OCR text near the cursor, app switches, clipboard copies, \
        and periodic screen captures with OCR.

        ## Event Timeline
        \(timeline)

        ## How to Read Events

        **CLICK events**: The user clicked something. "Near cursor" shows UI elements at the click point \
        (buttons, links, menu items, tabs). "On screen" shows surrounding visible text.

        **APPSWITCH events**: The user switched to a different app/window. OCR shows what was visible.

        **CLIPBOARD events**: The user copied text. "Content" shows what was copied.

        **SCREENSHOT events**: Periodic capture. OCR shows what was on screen at that moment.

        ## Pattern Recognition Guide

        Use these patterns to interpret raw events into meaningful steps:

        **Navigation pattern**: Multiple clicks in the same app with changing OCR = user is navigating through pages/menus.
        → Merge into: "Navigate to [destination] in [app]" or "Browse [section] on [site]"

        **Search pattern**: Click near search/input field → later OCR shows results or new content.
        → Merge into: "Search for [query] on [site/app]"

        **Selection pattern**: Multiple clicks on similar items, or click followed by clipboard copy.
        → Merge into: "Select [item] from [list/page]" or "Copy [content] from [source]"

        **Form/input pattern**: Clicks on fields, dropdowns, buttons like Submit/Save/Create.
        → Merge into: "Fill in [form] and submit" or "Configure [settings]"

        **Review pattern**: Mostly screenshots with changing OCR, few clicks = user reading/reviewing.
        → Merge into: "Review [content] in [app]"

        **Cross-app pattern**: App switch → action in new app → switch back = using one app to feed another.
        → Merge into: "Get [info] from [app A] to use in [app B]"

        **Website identification**: OCR containing URLs (like "freepik.com") or known site UI elements \
        (like "Explore", "Templates", "Dashboard") identifies which website/tool the user is on. \
        Use the site name, not just "Chrome".

        \(similarityHint ?? "")## Output Rules

        1. Merge related events into logical steps (don't list every click)
        2. Be SPECIFIC: use actual text from OCR (site names, button labels, section names)
        3. Describe INTENT not mechanics: "Browse design templates on Freepik" not "Clicked several things in Chrome"
        4. Each step should be a meaningful action a human would describe
        5. Include 3-8 steps (merge aggressively for short recordings, expand for long ones)
        6. For "tool", use the most specific option: the website/service name if identifiable

        Available tools: clipboard, chrome, notion_read, notion_write, google_sheets, \
        gmail, slack, linkedin, freepik, figma, canva, file_system, Claude, search, \
        or any specific website/service name you can identify from OCR.

        Respond ONLY with a JSON array:
        [
          {"index": 1, "description": "Open Freepik and navigate to Projects section", "tool": "freepik", "estimated_seconds": 10},
          {"index": 2, "description": "Browse Video Generator templates", "tool": "freepik", "estimated_seconds": 15}
        ]
        """

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

        DebugLog.log("[WorkflowExtractor] Raw AI output: \(output.prefix(500))")
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

            if let ocr = event.ocrContext, !ocr.isEmpty {
                line += "\n    OCR: \(ocr)"
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Parser

    private static func parseSteps(from output: String) -> [WorkflowStep] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if let steps = tryParseJSON(trimmed) { return steps }

        // Try to extract JSON from markdown code block or mixed output
        if let range = trimmed.range(of: "\\[\\s*\\{", options: .regularExpression),
           let endRange = trimmed.range(of: "\\}\\s*\\]", options: .regularExpression, range: range.lowerBound..<trimmed.endIndex) {
            let jsonStr = String(trimmed[range.lowerBound...endRange.upperBound])
            if let steps = tryParseJSON(jsonStr) { return steps }
        }

        DebugLog.log("[WorkflowExtractor] Failed to parse steps from output: \(trimmed.prefix(300))")
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
