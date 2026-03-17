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
        alog("[Autoclaw] deduce() called — clipboard: \(context.clipboard.prefix(80))…")

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
                process.arguments = [
                    "--model", "claude-haiku-4-5-20251001",
                    "--print",
                    prompt
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
                        // OAuth Access Token (sk-ant-oat01-...)
                        env["CLAUDE_CODE_OAUTH_TOKEN"] = apiKey
                        env.removeValue(forKey: "ANTHROPIC_API_KEY")
                    } else {
                        // Standard API key (sk-ant-api03-...)
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
                    // Read both pipes before waitUntilExit to avoid deadlock
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let output = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errMsg = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus != 0 {
                        alog("[Autoclaw] Haiku CLI exited \(process.terminationStatus)")
                        alog("[Autoclaw] stderr: \(errMsg.prefix(400))")
                        alog("[Autoclaw] stdout: \(output.prefix(400))")
                        continuation.resume(throwing: AutoclawError.parseError(
                            "Haiku exited \(process.terminationStatus): \(errMsg.prefix(200))"
                        ))
                        return
                    }

                    if output.isEmpty {
                        continuation.resume(throwing: AutoclawError.parseError("Haiku returned empty response"))
                        return
                    }

                    continuation.resume(returning: output)
                } catch {
                    alog("[Autoclaw] Haiku CLI failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Prompt

    private func buildPrompt(context: TaskContext) -> String {
        """
        You are Autoclaw, an ambient AI assistant embedded in a macOS app. The user just copied something to their clipboard while working. Your job is to deduce what task they need help with.

        ## Active Window Context
        - **App**: \(context.activeApp)
        - **Window title**: \(context.windowTitle)

        ## Clipboard Content
        ```
        \(context.clipboard)
        ```

        ## Instructions
        Based on the clipboard content and the active window context, deduce what the user needs.

        If you can confidently determine a task, respond with:
        {
          "type": "task",
          "title": "Short task title (max 10 words)",
          "draft": "The concrete draft output. Be specific and ready-to-use.",
          "skills": ["skill-1", "skill-2"],
          "completionPlan": "Step 1: ...\\nStep 2: ...\\nStep 3: ...",
          "confidence": 0.0 to 1.0
        }

        Skills should be an ordered list of tools/approaches needed. Examples:
        - ["code-edit"] for a single code change
        - ["research", "code-edit", "run-tests"] for research → implement → verify
        - ["reply-email"] for drafting a reply
        - ["create-github-issue", "code-edit", "create-pr"] for a full issue-to-PR workflow

        If you need more information or the task is ambiguous, respond with:
        {
          "type": "clarification",
          "question": "What specifically do you want to do with this?",
          "options": ["Option A", "Option B", "Option C"],
          "context": "Brief explanation of why you're asking"
        }

        Respond with ONLY valid JSON (no markdown fences).
        """
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

        let title = result["title"] as? String ?? "Task"
        let confidence = result["confidence"] as? Double ?? 0.5
        alog("[Autoclaw] Parsed suggestion: '\(title)' confidence=\(confidence) skills=\(skills)")

        return TaskSuggestion(
            title: title,
            draft: result["draft"] as? String ?? raw,
            skills: skills,
            completionPlan: result["completionPlan"] as? String,
            confidence: confidence,
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
