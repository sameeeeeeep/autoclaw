import Foundation
import os

private let logger = Logger(subsystem: "com.autoclaw.app", category: "deduction")

/// Log to os_log + file for debugging
private func alog(_ msg: String) {
    logger.info("\(msg, privacy: .public)")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/autoclaw_debug.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

final class TaskDeductionService: @unchecked Sendable {

    // MARK: - CLI Discovery (same as autoclawd)

    private static func findCLI() -> URL? {
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        if FileManager.default.isExecutableFile(atPath: localBin) {
            return URL(fileURLWithPath: localBin)
        }
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    // MARK: - Deduce via Claude CLI

    func deduce(context: TaskContext) async throws -> TaskSuggestion {
        let clipPreview = context.clipboardEntries.first?.content.prefix(80) ?? ""
        alog("[Autoclaw] deduce() called — \(context.clipboardEntries.count) clips, \(context.userMessages.count) msgs — first clip: \(clipPreview)…")

        guard let claudeURL = Self.findCLI() else {
            alog("[Autoclaw] claude CLI not found")
            throw AutoclawError.missingAPIKey("claude CLI not found. Install: npm install -g @anthropic-ai/claude-code")
        }
        alog("[Autoclaw] Using CLI: \(claudeURL.path)")

        let prompt = buildPrompt(context: context)

        // Shell out to `claude --model haiku --print <prompt>` for fast single-shot inference
        let response = try await callHaiku(claudeURL: claudeURL, prompt: prompt)

        alog("[Autoclaw] Haiku response (\(response.count) chars): \(response.prefix(300))")

        return try parseResponse(response)
    }

    // MARK: - Call Haiku via CLI (same approach as autoclawd)

    private func callHaiku(claudeURL: URL, prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = claudeURL
                // Use --output-format json to get token usage in the response
                process.arguments = [
                    "--model", "claude-haiku-4-5-20251001",
                    "-p", prompt,
                    "--output-format", "json"
                ]

                // Strip Claude Code env vars to avoid nested session guard
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")

                // Ensure API key is set — OAuth tokens (sk-ant-oat*) go to
                // CLAUDE_CODE_OAUTH_TOKEN, regular API keys go to ANTHROPIC_API_KEY
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
                        alog("[Autoclaw] Haiku CLI exited \(process.terminationStatus)")
                        alog("[Autoclaw] stderr: \(errMsg.prefix(400))")
                        alog("[Autoclaw] stdout: \(raw.prefix(400))")
                        continuation.resume(throwing: AutoclawError.parseError(
                            "Haiku exited \(process.terminationStatus): \(errMsg.prefix(200))"
                        ))
                        return
                    }

                    if raw.isEmpty {
                        continuation.resume(throwing: AutoclawError.parseError("Haiku returned empty response"))
                        return
                    }

                    // Parse the JSON envelope to extract result + log token usage
                    if let data = raw.data(using: .utf8),
                       let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Log token usage
                        if let usage = envelope["usage"] as? [String: Any] {
                            let inTok  = usage["input_tokens"]  as? Int ?? 0
                            let outTok = usage["output_tokens"] as? Int ?? 0
                            let cost   = envelope["total_cost_usd"] as? Double ?? 0
                            alog("[Autoclaw] Haiku tokens — in:\(inTok) out:\(outTok) cost:$\(String(format: "%.5f", cost))")
                        }
                        // Extract the actual model response text
                        if let result = envelope["result"] as? String {
                            continuation.resume(returning: result)
                            return
                        }
                    }

                    // Fallback: treat raw output as the response
                    alog("[Autoclaw] Warning: could not parse JSON envelope, using raw output")
                    continuation.resume(returning: raw)
                } catch {
                    alog("[Autoclaw] Haiku CLI failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Prompt

    private func buildPrompt(context: TaskContext) -> String {
        var sections: [String] = []

        sections.append("You are Autoclaw, an ambient AI assistant embedded in a macOS app. The user has been building up context — clipboard captures, messages, and possibly screenshots — and is now asking you to deduce what task they need help with.")

        // Clipboard entries
        if !context.clipboardEntries.isEmpty {
            sections.append("## Clipboard Captures")
            for (i, entry) in context.clipboardEntries.enumerated() {
                sections.append("""
                ### Capture \(i + 1)
                - **App**: \(entry.app)
                - **Window**: \(entry.window)
                ```
                \(entry.content)
                ```
                """)
            }
        }

        // User messages (explicit intent)
        if !context.userMessages.isEmpty {
            sections.append("## User Messages")
            for msg in context.userMessages {
                sections.append("- \"\(msg)\"")
            }
            sections.append("\nThe user messages above are explicit instructions about what they want. Prioritize these over guessing from clipboard content alone.")
        }

        // Screenshots
        if !context.screenshotPaths.isEmpty {
            sections.append("## Screenshots")
            sections.append("\(context.screenshotPaths.count) screenshot(s) were captured as additional context.")
        }

        sections.append("""
        ## Instructions
        Based on ALL the context above, deduce what the user needs AND determine the kind of response.

        Choose the correct "kind":
        - "execute" — task requires running code, making file changes, shell commands, git operations, creating PRs, etc. User needs Claude Code to act on their project.
        - "draft" — user needs a piece of text to use directly: email reply, message, document, commit message, PR description, etc. Output the ready-to-use text in "draft".
        - "answer" — user needs information, explanation, lookup, translation, summary, etc. Put the answer in "draft".

        Respond with:
        {
          "type": "task",
          "kind": "execute" | "draft" | "answer",
          "title": "Short title (max 10 words)",
          "draft": "The concrete output — ready-to-use text for draft/answer, or a description of the code change for execute.",
          "skills": ["skill-1", "skill-2"],
          "completionPlan": "Step 1: ...\\nStep 2: ...",
          "confidence": 0.0 to 1.0
        }

        For "execute" tasks, skills are the ordered tool chain:
        - ["code-edit"] for a single code change
        - ["research", "code-edit", "run-tests"] for research → implement → verify
        - ["create-github-issue", "code-edit", "create-pr"] for full issue-to-PR workflow
        For "draft" or "answer" tasks, skills can be empty or omitted.

        If the task is ambiguous or you need more information, respond with:
        {
          "type": "clarification",
          "question": "What specifically do you want to do with this?",
          "options": ["Option A", "Option B", "Option C"],
          "context": "Brief explanation of why you're asking"
        }

        Respond with ONLY valid JSON (no markdown fences).
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Parse Response (direct JSON from CLI --print output)

    private func parseResponse(_ raw: String) throws -> TaskSuggestion {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        alog("[Autoclaw] parseResponse input (\(cleaned.count) chars): \(cleaned.prefix(100))…")

        // Strip markdown fences if Haiku wraps them
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
            alog("[Autoclaw] Stripped fences, now \(cleaned.count) chars")
        }

        // Find JSON object in the response
        if let jsonStart = cleaned.firstIndex(of: "{"),
           let jsonEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[jsonStart...jsonEnd])
            alog("[Autoclaw] Extracted JSON (\(cleaned.count) chars): \(cleaned.prefix(100))…")
        }

        guard let resultData = cleaned.data(using: .utf8) else {
            alog("[Autoclaw] Failed to convert to data")
            throw AutoclawError.parseError("Failed to encode as UTF-8")
        }

        let result: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                alog("[Autoclaw] JSON parsed but not a dictionary")
                throw AutoclawError.parseError("JSON is not a dictionary")
            }
            result = parsed
        } catch {
            alog("[Autoclaw] JSON parse error: \(error). Content: \(cleaned.prefix(300))")
            throw AutoclawError.parseError("Failed to parse JSON: \(error.localizedDescription)")
        }

        alog("[Autoclaw] Parsed JSON keys: \(result.keys.sorted())")

        let responseType = result["type"] as? String ?? "task"

        // Handle clarification response
        if responseType == "clarification" {
            let clarification = Clarification(
                question: result["question"] as? String ?? "Need more information",
                options: result["options"] as? [String],
                context: result["context"] as? String
            )
            return TaskSuggestion(
                title: "Clarification needed",
                draft: clarification.question,
                skills: [],
                completionPlan: nil,
                confidence: 0,
                kind: .clarification,
                clarification: clarification
            )
        }

        // Parse skills — support both "skills" array and legacy "skill" string
        var skills: [String] = []
        if let skillArray = result["skills"] as? [String] {
            skills = skillArray
        } else if let single = result["skill"] as? String {
            skills = [single]
        }

        // Parse kind — default to .execute if skills present, else .answer
        let kindRaw = result["kind"] as? String ?? ""
        let kind: TaskKind
        switch kindRaw {
        case "draft":   kind = .draft
        case "answer":  kind = .answer
        case "execute": kind = .execute
        default:        kind = skills.isEmpty ? .answer : .execute
        }

        let title = result["title"] as? String ?? "Task"
        let confidence = result["confidence"] as? Double ?? 0.5
        alog("[Autoclaw] Parsed suggestion: '\(title)' kind=\(kind) confidence=\(confidence) skills=\(skills)")

        return TaskSuggestion(
            title: title,
            draft: result["draft"] as? String ?? raw,
            skills: skills,
            completionPlan: result["completionPlan"] as? String,
            confidence: confidence,
            kind: kind,
            clarification: nil
        )
    }
}

enum AutoclawError: LocalizedError {
    case missingAPIKey(String)
    case parseError(String)
    case executionError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): return msg
        case .parseError(let msg): return msg
        case .executionError(let msg): return msg
        }
    }
}
