import Foundation

final class ClaudeCodeRunner: @unchecked Sendable {

    // MARK: - CLI Discovery (same as autoclawd)

    static func findCLI() -> URL? {
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
        // Fall back to `which claude` in login shell (picks up nvm / volta / etc.)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let found = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    // MARK: - Execute (post-deduction approval)

    func execute(suggestion: TaskSuggestion, project: Project, sessionId: String?) -> AsyncThrowingStream<String, Error> {
        let prompt = buildExecutionPrompt(suggestion: suggestion, project: project)
        return runInteractiveSession(prompt: prompt, project: project, sessionId: sessionId)
    }

    // MARK: - Direct Execute (skip deduction)

    func executeDirect(prompt: String, project: Project, model: ClaudeModel, sessionId: String?) -> AsyncThrowingStream<String, Error> {
        return runInteractiveSession(prompt: prompt, project: project, model: model, sessionId: sessionId)
    }

    // MARK: - Interactive Session (like autoclawd — loads MCP connectors)

    /// Runs Claude Code in interactive mode with stream-json I/O.
    /// This mode loads all configured MCP servers (ClickUp, etc.) unlike -p/--print mode.
    private func runInteractiveSession(
        prompt: String,
        project: Project,
        model: ClaudeModel? = nil,
        sessionId: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let claudeURL = ClaudeCodeRunner.findCLI() else {
                        continuation.finish(throwing: AutoclawError.executionError("claude CLI not found"))
                        return
                    }

                    let process = Process()
                    process.executableURL = claudeURL

                    var args: [String] = [
                        "--output-format", "stream-json",
                        "--input-format", "stream-json",
                        "--verbose",
                        "--dangerously-skip-permissions",
                    ]
                    if let m = model {
                        args += ["--model", m.rawValue]
                    }
                    if let sid = sessionId {
                        args += ["--resume", sid]
                    }
                    process.arguments = args
                    process.currentDirectoryURL = URL(fileURLWithPath: project.path)

                    // Environment — pass API key, strip nested-session guards
                    var env = ProcessInfo.processInfo.environment
                    env.removeValue(forKey: "CLAUDECODE")
                    env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                    env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
                    env.removeValue(forKey: "ANTHROPIC_API_KEY")

                    let storedKey = AppSettings.shared.anthropicAPIKey
                    if !storedKey.isEmpty {
                        if storedKey.contains("-oat") {
                            env["CLAUDE_CODE_OAUTH_TOKEN"] = storedKey
                        } else {
                            env["ANTHROPIC_API_KEY"] = storedKey
                        }
                    }
                    process.environment = env

                    // Pipes
                    let stdinPipe = Pipe()
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardInput = stdinPipe
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()

                    // Send initial prompt via stdin as stream-json user message
                    let initialMsg: [String: Any] = [
                        "type": "user",
                        "message": [
                            "role": "user",
                            "content": prompt,
                        ],
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: initialMsg),
                       let json = String(data: data, encoding: .utf8) {
                        stdinPipe.fileHandleForWriting.write((json + "\n").data(using: .utf8)!)
                        print("[Autoclaw] Sent interactive prompt (\(prompt.count) chars)")
                    }

                    // Parse NDJSON from stdout using readabilityHandler
                    var stdoutBuffer = Data()
                    var finished = false

                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        if let text = String(data: data, encoding: .utf8) {
                            for line in text.components(separatedBy: "\n") where !line.isEmpty {
                                print("[Autoclaw] stderr: \(line.prefix(200))")
                            }
                        }
                    }

                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else {
                            // EOF
                            guard !finished else { return }
                            finished = true
                            stdoutPipe.fileHandleForReading.readabilityHandler = nil
                            stderrPipe.fileHandleForReading.readabilityHandler = nil
                            let status = process.terminationStatus
                            if status != 0 {
                                continuation.finish(throwing: AutoclawError.executionError(
                                    "Claude Code exited with status \(status)"))
                            } else {
                                continuation.finish()
                            }
                            return
                        }

                        stdoutBuffer.append(data)

                        // Process complete lines
                        while let newlineRange = stdoutBuffer.range(of: Data("\n".utf8)) {
                            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newlineRange.lowerBound)
                            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<newlineRange.upperBound)

                            guard let line = String(data: lineData, encoding: .utf8),
                                  !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                            guard let jsonData = line.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let type = json["type"] as? String else { continue }

                            // Extract text from events
                            if let text = Self.extractText(type: type, json: json) {
                                continuation.yield(text)
                            }
                        }
                    }

                    process.terminationHandler = { proc in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            guard !finished else { return }
                            finished = true
                            stdoutPipe.fileHandleForReading.readabilityHandler = nil
                            stderrPipe.fileHandleForReading.readabilityHandler = nil
                            // Close stdin to signal we're done
                            stdinPipe.fileHandleForWriting.closeFile()
                            let status = proc.terminationStatus
                            if status != 0 {
                                continuation.finish(throwing: AutoclawError.executionError(
                                    "Claude Code exited with status \(status)"))
                            } else {
                                continuation.finish()
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Event Text Extraction

    /// Extract displayable text from a stream-json event.
    private static func extractText(type: String, json: [String: Any]) -> String? {
        switch type {
        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var texts: [String] = []
                for block in content {
                    if block["type"] as? String == "text",
                       let text = block["text"] as? String {
                        texts.append(text)
                    }
                }
                return texts.isEmpty ? nil : texts.joined(separator: "\n")
            }

        case "result":
            let subtype = json["subtype"] as? String
            if subtype == "error" {
                return json["error"] as? String ?? json["result"] as? String
            }
            return json["result"] as? String

        case "stream_event":
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return nil }
            if eventType == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return text
            }

        default:
            break
        }
        return nil
    }

    // MARK: - Prompt Builder

    private func buildExecutionPrompt(suggestion: TaskSuggestion, project: Project) -> String {
        var prompt = """
        You are executing a task for the Autoclaw ambient AI system. Complete this task thoroughly.

        ## Task: \(suggestion.title)

        ## What to do
        \(suggestion.draft)
        """

        if let plan = suggestion.completionPlan {
            prompt += "\n\n## Execution Plan\n\(plan)"
        }

        if !suggestion.skills.isEmpty {
            let chain = suggestion.skills.joined(separator: " → ")
            prompt += "\n\n## Skill Chain: \(chain)"
            if suggestion.skills.count > 1 {
                prompt += "\nExecute each step in order. Complete one before moving to the next."
            }
        }

        prompt += """

        \n\n## Instructions
        - Execute the task completely — don't just describe what to do, actually do it.
        - Use all available tools: edit files, run commands, search the web, create ClickUp tasks, etc.
        - If this involves writing a reply or document, produce the final output.
        - If this involves code changes, make the actual edits.
        - Be thorough but concise in your output.
        """

        return prompt
    }
}
