import Foundation

final class ClaudeCodeRunner: @unchecked Sendable {

    func execute(suggestion: TaskSuggestion, project: Project, sessionId: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prompt = buildExecutionPrompt(suggestion: suggestion, project: project)

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    var args = [
                        "claude", "-p", prompt,
                        "--output-format", "stream-json",
                        "--allowedTools", "Edit,Write,Bash,Read,Glob,Grep,WebFetch,WebSearch"
                    ]
                    // Session-based threads: --resume keeps the conversation going
                    // within the same session so Claude has full context of prior tasks
                    if let sid = sessionId {
                        args += ["--resume", sid]
                    }
                    process.arguments = args
                    process.currentDirectoryURL = URL(fileURLWithPath: project.path)

                    // Pass through environment — handle both API keys and OAuth tokens
                    var env = ProcessInfo.processInfo.environment
                    env.removeValue(forKey: "CLAUDECODE")
                    env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")

                    let storedKey = AppSettings.shared.anthropicAPIKey
                    if !storedKey.isEmpty {
                        if storedKey.contains("-oat") {
                            env["CLAUDE_CODE_OAUTH_TOKEN"] = storedKey
                            env.removeValue(forKey: "ANTHROPIC_API_KEY")
                        } else {
                            env["ANTHROPIC_API_KEY"] = storedKey
                            env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
                        }
                    }
                    process.environment = env

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice

                    try process.run()

                    let handle = pipe.fileHandleForReading
                    var buffer = Data()

                    while process.isRunning || handle.availableData.count > 0 {
                        let chunk = handle.availableData
                        if chunk.isEmpty {
                            try await Task.sleep(nanoseconds: 50_000_000)
                            if !process.isRunning { break }
                            continue
                        }
                        buffer.append(chunk)

                        while let newlineRange = buffer.range(of: Data([0x0A])) {
                            let line = buffer[buffer.startIndex..<newlineRange.lowerBound]
                            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                            guard !line.isEmpty,
                                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                                continue
                            }

                            if let type = json["type"] as? String {
                                switch type {
                                case "assistant":
                                    if let message = json["message"] as? [String: Any],
                                       let content = message["content"] as? [[String: Any]] {
                                        for block in content {
                                            if let text = block["text"] as? String {
                                                continuation.yield(text)
                                            }
                                        }
                                    }
                                case "result":
                                    if let result = json["result"] as? String {
                                        continuation.yield(result)
                                    }
                                default:
                                    break
                                }
                            }
                        }
                    }

                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        continuation.finish(throwing: AutoclawError.executionError(
                            "Claude Code exited with status \(process.terminationStatus)"
                        ))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

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
        - Use all available tools: edit files, run commands, search the web, etc.
        - If this involves writing a reply or document, produce the final output.
        - If this involves code changes, make the actual edits.
        - Be thorough but concise in your output.
        """

        return prompt
    }
}
