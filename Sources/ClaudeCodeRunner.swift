import Foundation

// MARK: - Claude Session

/// An interactive streaming session with the Claude CLI.
/// Wraps the process and pipes for follow-up messages.
final class ClaudeSession: @unchecked Sendable {
    let sessionID: String
    private let process: Process
    private let stdinPipe: Pipe
    var isRunning = true

    init(sessionID: String, process: Process, stdinPipe: Pipe) {
        self.sessionID = sessionID
        self.process = process
        self.stdinPipe = stdinPipe
    }

    /// Send a follow-up message to Claude.
    func sendMessage(_ text: String) {
        guard isRunning else { return }
        let msg: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": text,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let json = String(data: data, encoding: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write((json + "\n").data(using: .utf8)!)
        print("[Autoclaw] ClaudeSession: sent follow-up (\(text.prefix(60))...)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stdinPipe.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }
    }

    deinit { stop() }
}

// MARK: - ClaudeCodeRunner

final class ClaudeCodeRunner: @unchecked Sendable {

    // MARK: - CLI Discovery

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

    func executeDirect(prompt: String, project: Project, model: ClaudeModel, sessionId: String?, singleShot: Bool = false) -> AsyncThrowingStream<String, Error> {
        return runInteractiveSession(prompt: prompt, project: project, model: model, sessionId: sessionId, singleShot: singleShot)
    }

    // MARK: - Interactive Session (ported from autoclawd)

    /// Runs Claude Code in interactive mode with stream-json I/O.
    /// Uses readabilityHandler for reliable pipe reading (FileHandle.bytes.lines
    /// doesn't work reliably with Process Pipes on macOS).
    private func runInteractiveSession(
        prompt: String,
        project: Project,
        model: ClaudeModel? = nil,
        sessionId: String? = nil,
        singleShot: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
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
                // Note: --resume requires a real Claude Code session ID (from system.init event),
                // not our internal session UUID. We'll capture and store the real ID later.
                // For now, each execution starts a fresh Claude session.
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
                    Self.setAuthEnv(storedKey, into: &env)
                } else {
                    print("[Autoclaw] WARNING: No API key in settings")
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

                let session = ClaudeSession(
                    sessionID: sessionId ?? UUID().uuidString,
                    process: process,
                    stdinPipe: stdinPipe
                )

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

                // Single-shot mode: close stdin so the process exits after responding
                if singleShot {
                    stdinPipe.fileHandleForWriting.closeFile()
                    print("[Autoclaw] Single-shot mode — stdin closed")
                }

                // Parse NDJSON from stdout using readabilityHandler
                var stdoutBuffer = Data()
                var stderrCollected = ""

                // Read stderr — collect for error reporting
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let text = String(data: data, encoding: .utf8) {
                        stderrCollected += text
                        for line in text.components(separatedBy: "\n") where !line.isEmpty {
                            print("[Autoclaw] stderr: \(line.prefix(300))")
                        }
                    }
                }

                // Read stdout and parse NDJSON events
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        // EOF on stdout pipe — stop reading but do NOT call terminationStatus here.
                        // The process may still be running; terminationHandler will handle cleanup.
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        return
                    }

                    stdoutBuffer.append(data)

                    // Split buffer on newlines and process complete lines
                    while let newlineRange = stdoutBuffer.range(of: Data("\n".utf8)) {
                        let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newlineRange.lowerBound)
                        stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<newlineRange.upperBound)

                        guard let line = String(data: lineData, encoding: .utf8),
                              !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                        guard let jsonData = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let type = json["type"] as? String else {
                            print("[Autoclaw] stream (non-JSON): \(line.prefix(300))")
                            // Yield non-JSON stderr-like output so user can see it
                            continuation.yield(line + "\n")
                            continue
                        }

                        let subtype = (json["subtype"] as? String) ?? ""
                        print("[Autoclaw] stream event: type=\(type) subtype=\(subtype)")

                        // Extract displayable text from the event
                        if let text = Self.extractText(type: type, json: json) {
                            continuation.yield(text)
                        }
                    }
                }

                // Handle process termination — give readabilityHandler time to drain
                process.terminationHandler = { [weak session] proc in
                    // Delay slightly so readabilityHandler can process any remaining buffered data
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        session?.isRunning = false
                        let status = proc.terminationStatus
                        if status != 0 {
                            let errDetail = stderrCollected.trimmingCharacters(in: .whitespacesAndNewlines)
                            let msg = errDetail.isEmpty
                                ? "Claude Code exited with status \(status)"
                                : "Claude Code exited with status \(status): \(String(errDetail.suffix(500)))"
                            print("[Autoclaw] ERROR (termination): \(msg)")
                            continuation.finish(throwing: AutoclawError.executionError(msg))
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

    // MARK: - Event Text Extraction (ported from autoclawd parseEvent)

    /// Extract displayable text from a stream-json event.
    private static func extractText(type: String, json: [String: Any]) -> String? {
        switch type {
        case "system":
            let subtype = json["subtype"] as? String
            if subtype == "init", let sid = json["session_id"] as? String {
                print("[Autoclaw] Session ID: \(sid)")
                return nil  // Don't display init events
            }
            return nil

        case "assistant":
            // Complete assistant message — extract text and tool info from content blocks
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var texts: [String] = []
                for block in content {
                    let blockType = block["type"] as? String
                    if blockType == "text", let text = block["text"] as? String {
                        texts.append(text)
                    } else if blockType == "tool_use" {
                        let name = block["name"] as? String ?? "unknown"
                        let input = block["input"] as? [String: Any]
                        let inputStr = formatToolInput(name: name, input: input)
                        if !inputStr.isEmpty {
                            texts.append("[\(name)] \(inputStr)")
                        }
                    }
                }
                return texts.isEmpty ? nil : texts.joined(separator: "\n")
            }
            return nil

        case "result":
            let subtype = json["subtype"] as? String
            let resultText = json["result"] as? String ?? ""
            if subtype == "error" {
                return json["error"] as? String ?? resultText
            }
            return resultText.isEmpty ? nil : resultText

        case "stream_event":
            // Partial streaming — extract from the raw Anthropic API event
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return nil }

            switch eventType {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any] {
                    let deltaType = delta["type"] as? String
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        return text
                    }
                }
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any],
                   block["type"] as? String == "tool_use",
                   let name = block["name"] as? String {
                    return "\n[\(name)] "
                }
            default:
                break
            }
            return nil

        default:
            return nil
        }
    }

    /// Format tool input into a human-readable summary.
    private static func formatToolInput(name: String, input: [String: Any]?) -> String {
        guard let input = input else { return "" }
        switch name {
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write", "Edit":
            return input["file_path"] as? String ?? ""
        case "Bash":
            return String((input["command"] as? String ?? "").prefix(120))
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        default:
            if let first = input.first {
                return "\(first.key)=\(String(describing: first.value).prefix(80))"
            }
            return ""
        }
    }

    // MARK: - Auth Helper (ported from autoclawd)

    /// Detects token type and sets the correct env var:
    /// - OAuth tokens (sk-ant-oat* or contains -oat) → CLAUDE_CODE_OAUTH_TOKEN
    /// - API keys → ANTHROPIC_API_KEY
    static func setAuthEnv(_ key: String, into env: inout [String: String]) {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        if cleaned.hasPrefix("sk-ant-oat") || cleaned.contains("-oat") {
            env["CLAUDE_CODE_OAUTH_TOKEN"] = cleaned
            print("[Autoclaw] Using OAuth token (len=\(cleaned.count))")
        } else {
            env["ANTHROPIC_API_KEY"] = cleaned
            print("[Autoclaw] Using API key (len=\(cleaned.count))")
        }
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
