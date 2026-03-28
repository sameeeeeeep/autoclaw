import Foundation

/// Sends rich context (app state + screen OCR + optional screenshot) to Haiku
/// for intelligent workflow/skill matching. Replaces the simple keyword overlap
/// in AnalyzePipeline.routeWithHaiku() with actual AI reasoning.
///
/// Input: what the user is doing right now (app, window, URL, recent events, OCR)
/// Output: matched workflow/skill chain with confidence and suggested steps
@MainActor
final class HaikuAnalyzer {

    // MARK: - Types

    struct MatchResult {
        let matchType: MatchType
        let matchedName: String          // workflow or skill name
        let confidence: Double           // 0-1
        let description: String          // what Haiku thinks the user is doing
        let suggestedSteps: [String]     // steps to execute
        let skillChain: [String]         // ordered skill names if chain detected
    }

    enum MatchType: String {
        case workflow       // matched a saved workflow
        case skill          // matched a preloaded skill/template
        case skillChain     // matched a chain of skills
        case custom         // no match, Haiku suggests custom approach
    }

    // MARK: - Public

    /// Analyze current context and match against known workflows/skills.
    /// Takes a screenshot for richer context when available.
    func analyze(
        activeApp: String,
        windowTitle: String,
        url: String?,
        recentActivity: String,
        screenOCR: String?,
        screenshotPath: String?,
        savedWorkflows: [SavedWorkflow],
        preloadedTemplates: [PreloadedTemplate],
        installedCapabilities: [CapabilityMap.Capability]
    ) async -> MatchResult? {

        // Build the catalog of things Haiku can match against
        let catalog = buildCatalog(
            workflows: savedWorkflows,
            templates: preloadedTemplates,
            capabilities: installedCapabilities
        )

        // Build context section
        var context = """
        CURRENT STATE:
        - Active app: \(activeApp)
        - Window: \(windowTitle)
        """
        if let u = url, !u.isEmpty {
            context += "\n- URL: \(u)"
        }
        if let ocr = screenOCR, !ocr.isEmpty {
            context += "\n- Screen text (OCR): \(ocr)"
        }
        if !recentActivity.isEmpty {
            context += "\n\nRECENT ACTIVITY (last 60s):\n\(recentActivity)"
        }

        let prompt = """
        Workflow detection engine. Match activity to skills. ONLY output JSON.

        CRITICAL: Only match if user took DELIBERATE ACTION (copied text, typed content, \
        clicked compose/create, switched apps with clear purpose). Mere presence in an app \
        (browsing, scrolling, watching, listening) is NOT actionable — output confidence 0.0. \
        For meetings: wait for END signals (leaving call, switching to notes app, typing). \
        Mid-meeting passive listening is never actionable.

        \(context)

        \(catalog)

        JSON: {"match_type":"workflow|skill|skill_chain|custom","matched_name":"name or empty",\
        "confidence":0.0,"description":"what user is doing","steps":["step1","step2"],\
        "skill_chain":["skill1","skill2"]}

        Rules:
        - "workflow": matches a saved workflow by name
        - "skill": matches a preloaded skill/template by name
        - "skill_chain": user needs MULTIPLE skills in sequence
        - "custom": nothing matches, describe what you'd do
        - confidence 0.0-1.0 (>0.6 = confident). No deliberate action = 0.0
        - Be conservative. Don't force matches.
        - steps: max 5 concrete steps
        """

        do {
            let raw = try await callCLI(prompt: prompt, model: "haiku")
            return parseResult(raw)
        } catch {
            print("[HaikuAnalyzer] Call failed: \(error)")
            return nil
        }
    }

    // MARK: - Catalog Builder

    private func buildCatalog(
        workflows: [SavedWorkflow],
        templates: [PreloadedTemplate],
        capabilities: [CapabilityMap.Capability]
    ) -> String {
        var catalog = "AVAILABLE WORKFLOWS AND SKILLS:\n\n"

        // Saved workflows (user-learned)
        if !workflows.isEmpty {
            catalog += "Saved workflows (user learned these):\n"
            for w in workflows {
                let steps = w.steps.prefix(5).map(\.description).joined(separator: " → ")
                let apps = Set(w.steps.compactMap(\.app)).joined(separator: ", ")
                catalog += "- \"\(w.name)\": \(steps)"
                if !apps.isEmpty { catalog += " [apps: \(apps)]" }
                catalog += "\n"
            }
            catalog += "\n"
        }

        // Preloaded templates/skills
        catalog += "Pre-loaded skills:\n"
        for t in templates {
            catalog += "- \"\(t.name)\": \(t.description) [apps: \(t.involvedApps.joined(separator: ", "))]\n"
        }
        catalog += "\n"

        // Installed MCP capabilities (abbreviated)
        let installed = capabilities.filter(\.isInstalled)
        if !installed.isEmpty {
            let grouped = Dictionary(grouping: installed, by: \.sourceApp)
            catalog += "Installed tools:\n"
            for (app, caps) in grouped.prefix(10) {
                let actions = caps.flatMap(\.actions).joined(separator: ", ")
                catalog += "- \(app): \(actions)\n"
            }
        }

        return catalog
    }

    // MARK: - Parse Response

    private func parseResult(_ raw: String) -> MatchResult? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[HaikuAnalyzer] Failed to parse response: \(raw.prefix(300))")
            return nil
        }

        let typeStr = json["match_type"] as? String ?? "custom"
        let matchType: MatchType
        switch typeStr {
        case "workflow": matchType = .workflow
        case "skill": matchType = .skill
        case "skill_chain": matchType = .skillChain
        default: matchType = .custom
        }

        let confidence = json["confidence"] as? Double ?? 0.0
        guard confidence >= 0.4 else { return nil } // skip low-confidence junk

        return MatchResult(
            matchType: matchType,
            matchedName: json["matched_name"] as? String ?? "",
            confidence: confidence,
            description: json["description"] as? String ?? "",
            suggestedSteps: json["steps"] as? [String] ?? [],
            skillChain: json["skill_chain"] as? [String] ?? []
        )
    }

    // MARK: - Claude CLI

    private func callCLI(prompt: String, model: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let localBin = home.appendingPathComponent(".local/bin/claude").path
                let candidates = [localBin, "/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
                guard let cliPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    continuation.resume(throwing: NSError(domain: "HaikuAnalyzer", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "claude CLI not found"]))
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = ["--model", model, "-p", prompt, "--output-format", "text", "--dangerously-skip-permissions"]

                let homePath = home.path
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = homePath
                let extraPaths = "\(homePath)/.local/bin:/usr/local/bin:/opt/homebrew/bin"
                env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "/usr/bin:/bin")"
                // Strip nested session vars
                for key in ["CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_THREAD_ID",
                            "CLAUDE_CODE_ENTRY_POINT", "CLAUDE_CODE_ENTRYPOINT",
                            "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
                            "CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES",
                            "CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL"] {
                    env.removeValue(forKey: key)
                }
                // Load OAuth token if not in env
                if env["CLAUDE_CODE_OAUTH_TOKEN"] == nil || env["CLAUDE_CODE_OAUTH_TOKEN"]?.isEmpty == true {
                    let credPath = home.appendingPathComponent(".claude/.credentials.json").path
                    if let data = FileManager.default.contents(atPath: credPath),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let oauth = json["claudeAiOauth"] as? [String: Any],
                       let token = oauth["accessToken"] as? String, !token.isEmpty {
                        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
                    }
                }
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let errOutput = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                    if process.terminationStatus != 0
                        || output.contains("\"type\":\"error\"")
                        || output.contains("authentication_error") {
                        let msg = !errOutput.isEmpty ? errOutput : output
                        continuation.resume(throwing: NSError(domain: "HaikuAnalyzer", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Haiku call failed: \(msg.prefix(300))"]))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
