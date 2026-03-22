import Foundation

/// Extracts structured workflow steps from a raw recording using Claude.
/// Combines OCR event timeline, key frame screenshots, capability map, and
/// optional Chrome extension DOM events for maximum extraction quality.
struct WorkflowExtractor {

    /// Extract logical workflow steps from a raw recording.
    /// - Parameters:
    ///   - recording: The raw recorded events (clicks, app switches, clipboard, screenshots)
    ///   - runner: Claude Code runner for AI inference
    ///   - model: Which model to use (Sonnet recommended for vision)
    ///   - savedWorkflows: Existing workflows for similarity matching
    ///   - screenshotPaths: Key frame images captured during recording (fed to vision)
    ///   - capabilities: Summary of installed MCP tools/capabilities
    ///   - domEvents: Structured DOM events from Chrome extension (if available)
    static func extractSteps(
        from recording: WorkflowRecording,
        model: ClaudeModel = .sonnet,
        savedWorkflows: [SavedWorkflow] = [],
        screenshotPaths: [String] = [],
        capabilities: String? = nil,
        domEvents: [BrowserDOMEvent] = []
    ) async throws -> [WorkflowStep] {

        let timeline = buildTimeline(from: recording, domEvents: domEvents)

        // Build similarity hint from saved workflows if available
        let matcher = await WorkflowMatcher()
        let similarityHint = await matcher.buildExtractionHint(
            events: recording.events,
            savedWorkflows: savedWorkflows
        )

        let prompt = buildPrompt(
            timeline: timeline,
            similarityHint: similarityHint,
            capabilities: capabilities,
            screenshotPaths: screenshotPaths,
            hasDOMEvents: !domEvents.isEmpty,
            eventCount: recording.events.count,
            duration: Int(recording.duration)
        )

        // Use simple CLI -p mode (like TaskDeductionService) instead of interactive stream-json.
        // Interactive mode is fragile and overkill for a single-shot extraction prompt.
        let output = try await callCLI(prompt: prompt, model: model)

        DebugLog.log("[WorkflowExtractor] Raw AI output (\(output.count) chars): \(output.prefix(500))")
        return parseSteps(from: output)
    }

    // MARK: - CLI Call (simple -p mode, same approach as TaskDeductionService)

    private static func callCLI(prompt: String, model: ClaudeModel) async throws -> String {
        guard let claudeURL = findCLI() else {
            throw AutoclawError.executionError("claude CLI not found. Install: npm install -g @anthropic-ai/claude-code")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = claudeURL
                process.arguments = [
                    "--model", model.rawValue,
                    "-p", prompt,
                    "--output-format", "json",
                    "--dangerously-skip-permissions"
                ]

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")

                let apiKey = AppSettings.shared.anthropicAPIKey
                if !apiKey.isEmpty {
                    if apiKey.contains("-oat") {
                        env["CLAUDE_CODE_OAUTH_TOKEN"] = apiKey
                        env.removeValue(forKey: "ANTHROPIC_API_KEY")
                    } else {
                        env["ANTHROPIC_API_KEY"] = apiKey
                        env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
                    }
                }
                process.environment = env

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let raw = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errMsg = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus != 0 {
                        DebugLog.log("[WorkflowExtractor] CLI exited \(process.terminationStatus): \(errMsg.prefix(300))")
                        continuation.resume(throwing: AutoclawError.executionError(
                            "CLI exited \(process.terminationStatus): \(errMsg.prefix(200))"
                        ))
                        return
                    }

                    if raw.isEmpty {
                        continuation.resume(throwing: AutoclawError.parseError("CLI returned empty response"))
                        return
                    }

                    // Parse JSON envelope to extract the result text
                    if let data = raw.data(using: .utf8),
                       let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let result = envelope["result"] as? String {
                        continuation.resume(returning: result)
                        return
                    }

                    // Fallback: use raw output
                    continuation.resume(returning: raw)
                } catch {
                    DebugLog.log("[WorkflowExtractor] CLI failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func findCLI() -> URL? {
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        if FileManager.default.isExecutableFile(atPath: localBin) {
            return URL(fileURLWithPath: localBin)
        }
        for path in ["/usr/local/bin/claude", "/opt/homebrew/bin/claude", "/usr/bin/claude"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    // MARK: - Prompt Builder

    private static func buildPrompt(
        timeline: String,
        similarityHint: String?,
        capabilities: String?,
        screenshotPaths: [String],
        hasDOMEvents: Bool,
        eventCount: Int,
        duration: Int
    ) -> String {
        var sections: [String] = []

        // System role
        sections.append("""
        You are a workflow extraction engine. You receive a timeline of user actions recorded on macOS \
        and must produce a precise, human-readable sequence of steps that describes what the user did — \
        at the level of detail a person would use to teach someone else the workflow.

        CRITICAL: Describe each step with SPECIFIC details — actual button names, actual field labels, \
        actual values entered, actual page names, actual URLs. Never say "Clicked in Chrome" — say \
        "Clicked 'Compose' button in Gmail" or "Navigated to mail.google.com/mail".
        """)

        // Event timeline
        sections.append("## Recorded Event Timeline (\(eventCount) events, \(duration)s)\n\n\(timeline)")

        // Screenshots (if available)
        if !screenshotPaths.isEmpty {
            var screenshotSection = """
            ## Key Frame Screenshots

            \(screenshotPaths.count) screenshots were captured during this recording. They show exactly what \
            was on screen at key moments. You MUST read each screenshot file below using the Read tool to see \
            the actual image content:

            """
            for (i, path) in screenshotPaths.enumerated() {
                screenshotSection += "\(i + 1). Read this file to see the screenshot: \(path)\n"
            }
            screenshotSection += """

            After reading all screenshots, use them to:
            1. Identify which app/website/page the user was on (look for logos, URLs, page titles)
            2. See exact button labels, form fields, menu items that were interacted with
            3. Read any text/data the user was working with
            4. Understand the visual context that OCR text alone might miss

            The screenshots are the ground truth — if OCR text is ambiguous, trust what you see in the images.
            """
            sections.append(screenshotSection)
        }

        // DOM events context (if Chrome extension provided them)
        if hasDOMEvents {
            sections.append("""
            ## Browser DOM Events

            The timeline includes DOM_* events from a Chrome extension. These are the highest-quality \
            signals — they give you exact CSS selectors, element types, form field names, URLs, and \
            values the user typed. Prioritize these over OCR when both are available.

            When you see a DOM_INPUT event with a value, include that value in the step description. \
            When you see a DOM_CLICK with a selector, use the element text/label not the selector.
            """)
        }

        // How to read events
        sections.append("""
        ## How to Read Events

        **CLICK events**: The user clicked something. "Near cursor" shows the text nearest to where \
        they clicked — this is usually the button/link/menu item they targeted. "On screen" shows \
        surrounding visible text for context.

        **APPSWITCH events**: The user switched to a different app or window. The window title and \
        any URL give you the destination.

        **CLIPBOARD events**: The user copied text. "Content" shows what was copied.

        **SCREENSHOT events**: Periodic screen capture. OCR shows what was visible.

        **DOM_CLICK events**: (from Chrome extension) Exact element clicked with CSS selector, \
        element text, tag name, and URL.

        **DOM_INPUT events**: (from Chrome extension) User typed into a form field. Includes \
        the field name/label and the value entered.

        **DOM_NAVIGATE events**: (from Chrome extension) User navigated to a new page. \
        Includes the full URL and page title.

        **DOM_SUBMIT events**: (from Chrome extension) User submitted a form.
        """)

        // Inference rules
        sections.append("""
        ## Inference Rules — How to Produce Proper Steps

        Your job is to INFER the user's intent from raw signals. Apply these rules:

        ### 1. Identify the App/Service First
        - OCR containing "gmail.com" or Gmail UI elements → user is in Gmail
        - OCR containing "notion.so" → user is in Notion
        - Window title "Slack" → user is in Slack
        - Use the SPECIFIC service name, never just "Chrome" or "browser"

        ### 2. Describe Actions at Human Level
        BAD: "Clicked near 'Compose' in Google Chrome"
        GOOD: "Open Gmail and click Compose to start a new email"

        BAD: "Clicked near 'To' then clipboard event"
        GOOD: "Enter recipient email address in the To field"

        BAD: "Multiple clicks in Chrome with changing OCR"
        GOOD: "Fill in the email subject as 'Weekly Status Update'"

        ### 3. Chain Related Events into Single Steps
        - Click on To field + type/paste email = "Enter recipient: user@example.com"
        - Click Compose + new compose window appears = "Click Compose to create new email"
        - Multiple clicks navigating menus = "Navigate to Settings > Account > Profile"
        - Click Send + confirmation = "Send the email"

        ### 4. Include Actual Data When Available
        - If clipboard content was "john@company.com" → include it: "Enter john@company.com in To field"
        - If OCR shows a subject line → include it: "Set subject to 'Q3 Report'"
        - If a URL was visited → include it: "Navigate to notion.so/workspace/project-page"
        - If a filename was involved → include it: "Upload report.pdf"

        ### 5. Recognize Common Workflows
        - Compose email: Open app → New/Compose → Fill To → Fill Subject → Write body → Send
        - Create task: Open PM tool → Click New → Fill title → Set assignee → Set due date → Save
        - Data transfer: Open source → Copy data → Switch to destination → Paste → Save
        - Research: Search → Browse results → Read page → Copy relevant info → Return
        - Form fill: Navigate to form → Fill fields one by one → Review → Submit
        """)

        // Capabilities
        if let caps = capabilities, !caps.isEmpty {
            sections.append("""
            ## Available Automation Capabilities

            These MCP tools are installed and can be used to REPLAY this workflow automatically. \
            Map each step to the most specific tool that could execute it:

            \(caps)

            When choosing the "tool" field, prefer these installed capability names over generic ones. \
            For example, if "Chrome MCP" is available, use "chrome_navigate" and "chrome_click" instead \
            of generic "gmail". If "ClickUp MCP" is available, use "clickup_create_task" instead of "clickup".
            """)
        } else {
            sections.append("""
            ## Available Tools

            Use the most specific tool name you can identify from the workflow:
            clipboard, chrome_navigate, chrome_click, chrome_form_input, notion_read, notion_write, \
            google_sheets_read, google_sheets_write, gmail_compose, gmail_send, slack_send, \
            github_create_issue, github_create_pr, clickup_create_task, file_read, file_write, \
            terminal, web_search, or any specific website/service name from the recording.
            """)
        }

        // Similarity hint
        if let hint = similarityHint {
            sections.append(hint)
        }

        // Output format
        sections.append("""
        ## Output Format

        Respond with ONLY a JSON array. No markdown fences, no explanation.

        Each step must have:
        - "index": Sequential number starting at 1
        - "description": Detailed human-readable description with specific names, values, labels
        - "tool": The most specific tool/service that would execute this step
        - "estimated_seconds": How long this step typically takes a human
        - "details": Object with extracted specifics (optional but preferred):
          - "app": The specific app or website (e.g. "Gmail", "Notion", "ClickUp")
          - "action": The specific action (e.g. "click", "type", "navigate", "copy", "paste", "send")
          - "target": What was acted on (e.g. "Compose button", "To field", "Send button")
          - "value": Any value entered/selected (e.g. "user@email.com", "Weekly Update")
          - "url": URL if applicable
          - "selector": CSS selector if available from DOM events

        Example output for "user composes and sends a Gmail email":
        [
          {"index": 1, "description": "Open Gmail in Chrome", "tool": "chrome_navigate", "estimated_seconds": 3, "details": {"app": "Gmail", "action": "navigate", "url": "mail.google.com"}},
          {"index": 2, "description": "Click Compose to start a new email", "tool": "chrome_click", "estimated_seconds": 2, "details": {"app": "Gmail", "action": "click", "target": "Compose button"}},
          {"index": 3, "description": "Enter recipient email address 'sameep@company.com' in To field", "tool": "chrome_form_input", "estimated_seconds": 5, "details": {"app": "Gmail", "action": "type", "target": "To field", "value": "sameep@company.com"}},
          {"index": 4, "description": "Set email subject to 'Weekly Status Update'", "tool": "chrome_form_input", "estimated_seconds": 3, "details": {"app": "Gmail", "action": "type", "target": "Subject field", "value": "Weekly Status Update"}},
          {"index": 5, "description": "Write email body with project status details", "tool": "chrome_form_input", "estimated_seconds": 30, "details": {"app": "Gmail", "action": "type", "target": "Email body"}},
          {"index": 6, "description": "Click Send to deliver the email", "tool": "chrome_click", "estimated_seconds": 2, "details": {"app": "Gmail", "action": "click", "target": "Send button"}}
        ]
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Timeline Builder

    private static func buildTimeline(from recording: WorkflowRecording, domEvents: [BrowserDOMEvent] = []) -> String {
        var lines: [String] = []
        lines.append("Duration: \(Int(recording.duration))s | Events: \(recording.events.count)")
        if !domEvents.isEmpty {
            lines.append("Chrome DOM events: \(domEvents.count) (high-quality browser signals)")
        }
        lines.append("")

        // Merge OCR events and DOM events by timestamp
        struct TimelineEntry: Comparable {
            let timestamp: Date
            let elapsed: TimeInterval
            let line: String
            static func < (lhs: TimelineEntry, rhs: TimelineEntry) -> Bool {
                lhs.timestamp < rhs.timestamp
            }
        }

        var entries: [TimelineEntry] = []

        // Add OCR-based events
        for event in recording.events {
            let time = event.elapsedFormatted
            let type = event.type.rawValue.uppercased()
            var line = "[\(time)] \(type) — \(event.description)"

            if let data = event.data, !data.isEmpty {
                let preview = String(data.prefix(300))
                line += "\n    Content: \"\(preview)\""
            }

            if let ocr = event.ocrContext, !ocr.isEmpty {
                line += "\n    OCR: \(ocr)"
            }

            entries.append(TimelineEntry(
                timestamp: event.timestamp,
                elapsed: event.elapsed,
                line: line
            ))
        }

        // Add DOM events from Chrome extension
        let recordingStart = recording.startedAt
        for domEvent in domEvents {
            let elapsed = domEvent.timestamp.timeIntervalSince(recordingStart)
            let m = Int(elapsed) / 60
            let s = Int(elapsed) % 60
            let time = String(format: "%d:%02d", m, s)

            var line = "[\(time)] DOM_\(domEvent.type.rawValue.uppercased()) — "

            switch domEvent.type {
            case .click:
                line += "Clicked '\(domEvent.elementText ?? domEvent.selector ?? "unknown")'"
                if let tag = domEvent.tagName { line += " (\(tag))" }
                if let url = domEvent.url { line += " on \(url)" }
                if let sel = domEvent.selector { line += "\n    Selector: \(sel)" }

            case .input:
                let field = domEvent.fieldName ?? domEvent.selector ?? "field"
                let value = domEvent.value ?? ""
                line += "Typed '\(value)' into \(field)"
                if let sel = domEvent.selector { line += "\n    Selector: \(sel)" }

            case .navigate:
                let url = domEvent.url ?? "unknown"
                let title = domEvent.pageTitle ?? ""
                line += "Navigated to \(url)"
                if !title.isEmpty { line += " — \"\(title)\"" }

            case .submit:
                line += "Submitted form"
                if let url = domEvent.url { line += " on \(url)" }

            case .select:
                let field = domEvent.fieldName ?? "dropdown"
                let value = domEvent.value ?? ""
                line += "Selected '\(value)' in \(field)"
            }

            entries.append(TimelineEntry(
                timestamp: domEvent.timestamp,
                elapsed: elapsed,
                line: line
            ))
        }

        // Sort by timestamp and build output
        entries.sort()
        lines.append(contentsOf: entries.map(\.line))

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Parser

    private static func parseSteps(from output: String) -> [WorkflowStep] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if let steps = tryParseJSON(trimmed) { return steps }

        // Strip markdown fences if present
        var cleaned = trimmed
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        if let steps = tryParseJSON(cleaned) { return steps }

        // Try to extract JSON array from mixed output
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
            let details: StepDetails?
        }

        struct StepDetails: Decodable {
            let app: String?
            let action: String?
            let target: String?
            let value: String?
            let url: String?
            let selector: String?
        }

        guard let rawSteps = try? JSONDecoder().decode([RawStep].self, from: data) else { return nil }

        return rawSteps.map { raw in
            WorkflowStep(
                index: raw.index,
                description: raw.description,
                tool: raw.tool,
                estimatedSeconds: raw.estimated_seconds,
                app: raw.details?.app,
                action: raw.details?.action,
                target: raw.details?.target,
                value: raw.details?.value,
                url: raw.details?.url,
                selector: raw.details?.selector
            )
        }
    }
}

// MARK: - Browser DOM Event (from Chrome Extension)

/// Structured event captured by the Autoclaw Chrome extension via WebSocket.
/// Much higher quality than OCR — gives exact selectors, values, and URLs.
struct BrowserDOMEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let url: String?
    let pageTitle: String?
    let selector: String?         // CSS selector of the element
    let tagName: String?          // button, input, a, select, etc.
    let elementText: String?      // visible text of the element
    let fieldName: String?        // form field name/label/aria-label
    let value: String?            // value entered (for input events)
    let formAction: String?       // form action URL (for submit events)

    enum EventType: String, Codable {
        case click
        case input
        case navigate
        case submit
        case select
    }

    init(
        type: EventType,
        url: String? = nil,
        pageTitle: String? = nil,
        selector: String? = nil,
        tagName: String? = nil,
        elementText: String? = nil,
        fieldName: String? = nil,
        value: String? = nil,
        formAction: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.url = url
        self.pageTitle = pageTitle
        self.selector = selector
        self.tagName = tagName
        self.elementText = elementText
        self.fieldName = fieldName
        self.value = value
        self.formAction = formAction
    }
}
