import Foundation
import Combine
import AppKit

// MARK: - Transcribe Service

/// Orchestrates the voice-to-cursor pipeline:
/// Record → background chunk transcription → on stop, combine raw chunks → inject at cursor → enhance in background.
///
/// Background loop every ~25s: transcribe audio chunk → store raw text.
/// On stop: drain remaining chunks → combine all raw text → inject immediately → enhance (non-blocking).
/// User sees "Listening..." while recording, then raw text appears instantly, enhanced version offered after.
@MainActor
final class TranscribeService: ObservableObject {
    @Published var status: TranscribeStatus = .idle
    @Published var rawText = ""
    @Published var cleanText = ""
    @Published var enhancedText = ""
    @Published var isEnhancing = false
    /// Pre-prompt suggestion generated from project + session context before user speaks
    @Published var suggestedPrompts: [String] = []  // Two suggestions
    @Published var isGeneratingPrompt = false

    /// Legacy single suggestion accessor (first of two)
    var suggestedPrompt: String { suggestedPrompts.first ?? "" }

    private let voiceService: VoiceService
    private let ollamaService: OllamaService

    /// The app user was in when they started transcribing
    var activeApp: String = ""
    /// Project context (CLAUDE.md summary) — set by AppState before start
    var projectContext: String = ""
    /// Session context (recent thread messages) — set by AppState before start
    var sessionContext: String = ""

    /// Raw transcribed chunks accumulated during background processing
    private var rawChunks: [String] = []
    /// Background processing task
    private var backgroundTask: Task<Void, Never>?
    /// Pre-prompt generation task
    private var promptTask: Task<Void, Never>?

    /// Persistent Haiku session ID — context loaded once, reused for all pre-prompts
    private var haikuSessionId: String?
    /// Whether the Haiku session has been primed with project+session context
    private var haikuSessionPrimed = false
    /// Auto-refresh loop that watches for new session activity
    private var autoRefreshTask: Task<Void, Never>?
    /// Callback to get latest session context (set by AppState)
    var sessionContextProvider: (() -> String)?
    /// Last session context hash — only refresh when it changes
    private var lastSessionContextHash: Int = 0

    /// How often to transcribe a chunk (seconds)
    private let chunkInterval: Float = 25.0

    init(voiceService: VoiceService, ollamaService: OllamaService) {
        self.voiceService = voiceService
        self.ollamaService = ollamaService
    }

    // MARK: - Public

    /// Enhance clipboard text without voice
    func enhanceClipboard(_ text: String, app: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        rawText = trimmed
        cleanText = trimmed
        enhancedText = ""
        activeApp = app
        status = .done

        Task { @MainActor in
            await enhanceWithModel(text: trimmed, app: app)
        }
    }

    /// Force reset all state — used by endSession() to ensure clean slate for next session
    func forceReset() {
        backgroundTask?.cancel()
        backgroundTask = nil
        promptTask?.cancel()
        promptTask = nil
        rawChunks = []
        rawText = ""
        cleanText = ""
        enhancedText = ""
        suggestedPrompts = []
        isEnhancing = false
        isGeneratingPrompt = false
        status = .idle
        print("[Transcribe] Force reset — ready for new session")
    }

    /// Start recording — shows "Listening..." to user, background processes chunks
    func start() {
        guard status == .idle || status == .done || status.isError else {
            DebugLog.log("[Transcribe] Cannot start — status is \(status.label), forcing reset")
            forceReset()
            return start()
        }

        rawText = ""
        cleanText = ""
        enhancedText = ""
        rawChunks = []
        status = .listening

        DebugLog.log("[Transcribe] Starting recording (backend: \(voiceService.activeBackend.rawValue), whisperKit loaded: \(voiceService.whisperKitService.isModelLoaded))")
        voiceService.startListening()

        // Start background chunk processing (transcribe + clean every ~25s)
        startBackgroundProcessing()
    }

    /// Stop recording → drain all chunks → combine raw text → inject immediately → enhance in background
    func stop() {
        guard status == .listening else {
            status = .idle
            return
        }

        // Stop background processing
        backgroundTask?.cancel()
        backgroundTask = nil

        status = .transcribing
        DebugLog.log("[Transcribe] Stopping, processing final chunk...")

        Task { @MainActor in
            let whisperKit = voiceService.whisperKitService

            // 1. Pre-stop drain: grab any chunks WhisperKit completed but we haven't pulled yet
            let preStopChunks = whisperKit.takeCompletedChunks()
            if !preStopChunks.isEmpty {
                DebugLog.log("[Transcribe] Pre-stop drain: \(preStopChunks.count) unclaimed chunk(s)")
                for chunk in preStopChunks {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { rawChunks.append(trimmed) }
                }
            }

            // 2. Stop recording and transcribe remaining audio
            DebugLog.log("[Transcribe] Calling stopAndTranscribe...")
            let remainingRaw = await voiceService.stopAndTranscribe()
            let remainingTrimmed = remainingRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.log("[Transcribe] Remaining from WhisperKit (\(remainingTrimmed.count) chars): \(remainingTrimmed.prefix(200))")

            // 3. Post-stop drain: catch any chunk WhisperKit's bg loop finished during stop
            //    (edge case: WhisperKit was mid-transcription when we did pre-stop drain)
            let postStopChunks = whisperKit.takeCompletedChunks()
            if !postStopChunks.isEmpty {
                DebugLog.log("[Transcribe] Post-stop drain: \(postStopChunks.count) late chunk(s)")
                for chunk in postStopChunks {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { rawChunks.append(trimmed) }
                }
            }

            // 4. Add remaining audio
            if !remainingTrimmed.isEmpty {
                rawChunks.append(remainingTrimmed)
            }

            // 5. Combine all raw chunks → inject immediately (no cleanup delay)
            let fullRaw = rawChunks
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DebugLog.log("[Transcribe] Combined \(rawChunks.count) chunks (\(fullRaw.count) chars): \(fullRaw.prefix(200))")

            guard !fullRaw.isEmpty else {
                DebugLog.log("[Transcribe] Empty result — nothing to inject")
                status = .idle
                return
            }

            rawText = fullRaw
            cleanText = fullRaw

            // 6. Inject raw text at cursor IMMEDIATELY — no cleanup wait
            await injectText(fullRaw)

            // 7. Smart enhance in background (replaces old cleanup + enhance two-step)
            let app = activeApp
            Task { @MainActor in
                await enhanceWithModel(text: fullRaw, app: app)
            }

            // 8. Feed transcribed text back to Haiku session → get fresh predictions
            feedHaikuAndRefresh(userSaid: fullRaw)
        }
    }

    /// Feed what the user just said back to the persistent Haiku session and get updated predictions
    private func feedHaikuAndRefresh(userSaid text: String) {
        guard haikuSessionPrimed, let sessionId = haikuSessionId else { return }

        promptTask?.cancel()
        isGeneratingPrompt = true

        promptTask = Task { @MainActor in
            defer { isGeneratingPrompt = false }

            let followUp = "User just dictated: \"\(String(text.prefix(500)))\". Reply ONLY as:\nA: <prediction>\nB: <prediction>\nGO:"

            do {
                let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)
                parsePrePromptResult(result)
            } catch {
                DebugLog.log("[PrePrompt] Feed-back failed: \(error)")
            }
        }
    }

    // MARK: - Background Chunk Processing

    /// Runs in background: every ~25s, pulls completed transcription chunks from WhisperKit.
    /// No cleanup — just accumulates raw text. Cleanup is skipped for speed; enhance handles quality.
    private func startBackgroundProcessing() {
        backgroundTask = Task { @MainActor in
            while !Task.isCancelled {
                // Wait for chunk interval
                try? await Task.sleep(nanoseconds: UInt64(chunkInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Pull any completed chunks from WhisperKit
                let whisperKit = voiceService.whisperKitService
                let chunks = whisperKit.takeCompletedChunks()

                for chunk in chunks {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    rawChunks.append(trimmed)
                    print("[Transcribe] Background chunk \(rawChunks.count): \(trimmed.prefix(80))...")
                }
            }
        }
    }

    // MARK: - Auto-Refresh Loop

    /// Start watching for new session activity — refreshes predictions when the Claude Code session changes
    func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                // Check every 15 seconds for new session activity
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                guard haikuSessionPrimed, let sessionId = haikuSessionId else { continue }

                // Get fresh session context and check if it changed
                guard let provider = sessionContextProvider else { continue }
                let freshContext = provider()
                let freshHash = freshContext.hashValue
                guard freshHash != lastSessionContextHash, !freshContext.isEmpty else { continue }
                lastSessionContextHash = freshHash

                // Session changed — tell Haiku and get new predictions
                DebugLog.log("[PrePrompt] Session activity changed, refreshing predictions...")
                isGeneratingPrompt = true
                defer { isGeneratingPrompt = false }

                let followUp = "Session activity update:\n\(String(freshContext.suffix(800)))\n\nReply ONLY as:\nA: <prediction>\nB: <prediction>\nGO:"

                do {
                    let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)
                    parsePrePromptResult(result)
                } catch {
                    DebugLog.log("[PrePrompt] Auto-refresh failed: \(error)")
                }
            }
        }
    }

    /// Stop the auto-refresh loop
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Pre-Prompt Generation

    /// Reset the persistent Haiku session (call when project/session changes)
    func resetHaikuSession() {
        haikuSessionId = nil
        haikuSessionPrimed = false
    }

    /// Generate contextual prompt suggestions based on project + session + active app.
    /// Uses a persistent Haiku session — context loaded once, predictions are lightweight follow-ups.
    /// Returns 2 suggestions so the user can pick the most relevant one.
    func generatePrePrompt() {
        // Need context to generate a suggestion
        guard !projectContext.isEmpty || !sessionContext.isEmpty else {
            DebugLog.log("[PrePrompt] SKIP — projectContext: \(projectContext.count) chars, sessionContext: \(sessionContext.count) chars")
            return
        }

        promptTask?.cancel()
        suggestedPrompts = []
        isGeneratingPrompt = true
        DebugLog.log("[PrePrompt] STARTED — project: \(projectContext.count) chars, session: \(sessionContext.count) chars, app: \(activeApp), haiku session: \(haikuSessionId ?? "new")")

        promptTask = Task { @MainActor in
            defer {
                isGeneratingPrompt = false
                DebugLog.log("[PrePrompt] DONE — \(suggestedPrompts.count) suggestions")
            }

            do {
                // First call: prime the session with full context
                if !haikuSessionPrimed {
                    let sessionId = UUID().uuidString
                    haikuSessionId = sessionId

                    var contextBlock = ""
                    if !projectContext.isEmpty {
                        contextBlock += "PROJECT:\n\(projectContext)\n\n"
                    }
                    if !sessionContext.isEmpty {
                        contextBlock += "SESSION:\n\(sessionContext)\n\n"
                    }
                    contextBlock += "Active app: \(activeApp)"

                    let primePrompt = """
                    You are a parallel AI session that tracks what a developer is doing and predicts what they'll say next via voice-to-text.

                    \(contextBlock)

                    PROJECT is what this project is about. SESSION is what the user has been doing right now.
                    You will be asked repeatedly: "what will the user say next?"

                    Reply format (STRICTLY follow, no other text):
                    A: <prediction 1, under 100 chars>
                    B: <prediction 2, under 100 chars>

                    Think about branching possibilities — did the last thing work or not? Continuing or pivoting?
                    Focus on SESSION flow, not project backlog. Write as the user speaking to an AI assistant.

                    GO:
                    """

                    DebugLog.log("[PrePrompt] Priming Haiku session \(sessionId)...")
                    let result = try await callClaudeCLI(prompt: primePrompt, model: "haiku", sessionId: sessionId)
                    haikuSessionPrimed = true
                    // Seed the hash so auto-refresh doesn't immediately re-fire
                    if let provider = sessionContextProvider {
                        lastSessionContextHash = provider().hashValue
                    }
                    parsePrePromptResult(result)

                } else if let sessionId = haikuSessionId {
                    // Follow-up: just ask for next prediction (context already loaded)
                    let followUp = "Active app: \(activeApp). Reply ONLY as:\nA: <prediction>\nB: <prediction>\nGO:"

                    DebugLog.log("[PrePrompt] Resuming Haiku session \(sessionId)...")
                    let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)
                    parsePrePromptResult(result)
                }
            } catch {
                DebugLog.log("[PrePrompt] FAILED: \(error)")
            }
        }
    }

    /// Parse Haiku's response into 2 suggestions
    private func parsePrePromptResult(_ result: String) {
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard !Task.isCancelled else {
            DebugLog.log("[PrePrompt] CANCELLED")
            return
        }

        guard !cleaned.isEmpty && !cleaned.contains("\"type\":\"error\"") && !cleaned.hasPrefix("{") else {
            DebugLog.log("[PrePrompt] Bad result: \"\(cleaned.prefix(100))\"")
            return
        }

        // Extract A: and B: lines
        var prompts: [String] = []
        for line in cleaned.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match "A: ..." or "B: ..." (the format we asked for)
            if let range = trimmed.range(of: #"^[AB]:\s*"#, options: .regularExpression) {
                var prediction = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    .replacingOccurrences(of: "**", with: "")
                if !prediction.isEmpty && prediction.count > 5 {
                    prompts.append(prediction)
                }
            }
            if prompts.count >= 2 { break }
        }

        // Fallback: if Haiku didn't use A:/B: format, take first 2 non-empty lines that aren't headers
        if prompts.isEmpty {
            let fallback = cleaned.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") }
                .map { line -> String in
                    var l = line
                    if let range = l.range(of: #"^[0-9]+[\.\)]\s*"#, options: .regularExpression) { l.removeSubrange(range) }
                    if l.hasPrefix("- ") { l = String(l.dropFirst(2)) }
                    return l.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                .filter { !$0.isEmpty && $0.count > 5 && !$0.hasSuffix(":") }
            prompts = Array(fallback.prefix(2))
        }

        suggestedPrompts = prompts
        DebugLog.log("[PrePrompt] Parsed \(suggestedPrompts.count) suggestions: \(suggestedPrompts)")
    }

    // MARK: - Injection

    /// Inject a specific pre-prompt suggestion at cursor
    func injectPrePrompt(at index: Int = 0) {
        guard index < suggestedPrompts.count else { return }
        let text = suggestedPrompts[index]
        guard !text.isEmpty else { return }
        suggestedPrompts = []
        Task { @MainActor in
            await CursorInjector.type(text)
            print("[Transcribe] Injected pre-prompt: \(text.prefix(60))...")
        }
    }

    private func injectText(_ text: String) async {
        status = .injecting
        print("[Transcribe] Injecting at cursor: \(text.prefix(60))...")
        await CursorInjector.type(text)
        status = .done
        print("[Transcribe] Injected successfully")
    }

    func injectEnhanced() async {
        guard !enhancedText.isEmpty else { return }
        status = .injecting
        await CursorInjector.selectAllAndReplace(enhancedText)
        cleanText = enhancedText
        status = .done
    }

    // MARK: - Smart Enhancement

    private func enhanceWithModel(text: String, app: String) async {
        let provider = AppSettings.shared.enhanceProvider
        guard provider != .none else { return }

        isEnhancing = true
        enhancedText = ""

        let appContext: String
        switch app.lowercased() {
        case let a where a.contains("gmail") || a.contains("mail"):
            appContext = "email — professional and clear"
        case let a where a.contains("slack") || a.contains("discord") || a.contains("teams"):
            appContext = "messaging — casual but clear"
        case let a where a.contains("notion") || a.contains("docs") || a.contains("word"):
            appContext = "document — polished and flowing"
        case let a where a.contains("twitter") || a.contains("x.com") || a.contains("linkedin"):
            appContext = "social media — punchy and engaging"
        case let a where a.contains("terminal") || a.contains("xcode") || a.contains("code"):
            appContext = "code/terminal — technical and precise"
        default:
            appContext = "general — clear and effective"
        }

        // Build context block from project + session (if available)
        var contextBlock = ""
        if !projectContext.isEmpty {
            contextBlock += "\nProject context:\n\(projectContext)\n"
        }
        if !sessionContext.isEmpty {
            contextBlock += "\nRecent session activity:\n\(sessionContext)\n"
        }

        // Include pre-prompt prediction for continuity (same "thread" of understanding)
        var predictionHint = ""
        if !suggestedPrompt.isEmpty {
            predictionHint = "\nPredicted intent: \(suggestedPrompt)\n"
        }

        let prompt: String
        if contextBlock.isEmpty && predictionHint.isEmpty {
            prompt = """
            Rewrite this dictated text to be better. Keep the user's voice and meaning. \
            Make it sharper and clearer. If it's already good, return it mostly as-is. \
            Tone: \(appContext). Active app: \(app). \
            Return ONLY the improved text, nothing else.

            "\(text)"
            """
        } else {
            prompt = """
            Enhance this dictated text. You have full context of what the user is working on. \
            Be PROACTIVE — don't just clean up grammar: \
            - Add specific details from the project/session context (file names, function names, variable names) \
            - If the user is giving an instruction, make it more complete and actionable \
            - If the user is describing a problem, add technical specifics they might have skipped while speaking \
            - If the user mentions something vague, fill in the concrete details from context \
            Keep their voice and intent, but make it the version they WISH they'd said. \
            Tone: \(appContext). Active app: \(app).
            \(contextBlock)\(predictionHint)
            Return ONLY the enhanced text, nothing else.

            "\(text)"
            """
        }

        do {
            let result = try await callClaudeCLI(prompt: prompt, model: provider.modelFlag)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // Guard against API errors leaking into the UI
            if !cleaned.isEmpty && cleaned != text
                && !cleaned.contains("\"type\":\"error\"")
                && !cleaned.contains("authentication_error")
                && !cleaned.contains("Failed to authenticate")
                && !cleaned.hasPrefix("{") {
                enhancedText = cleaned
                print("[Transcribe] Enhanced: \(cleaned.prefix(80))...")
            } else if !cleaned.isEmpty {
                print("[Transcribe] Enhancement returned error/garbage, discarding: \(cleaned.prefix(200))")
            }
        } catch {
            print("[Transcribe] Enhancement failed: \(error)")
        }

        isEnhancing = false
    }

    // MARK: - Claude CLI

    private func callClaudeCLI(prompt: String, model: String = "haiku", sessionId: String? = nil, resume: Bool = false) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let localBin = home.appendingPathComponent(".local/bin/claude").path
                let candidates = [localBin, "/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
                guard let cliPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    continuation.resume(throwing: NSError(domain: "Transcribe", code: 1, userInfo: [NSLocalizedDescriptionKey: "claude CLI not found"]))
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                var args = ["--model", model, "-p", prompt, "--output-format", "text", "--dangerously-skip-permissions"]
                if let sid = sessionId {
                    if resume {
                        args += ["--resume", sid]
                    } else {
                        args += ["--session-id", sid]
                    }
                }
                process.arguments = args

                let homePath = home.path
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = homePath
                // Ensure claude CLI is on PATH — prepend common locations
                let extraPaths = "\(homePath)/.local/bin:/usr/local/bin:/opt/homebrew/bin"
                let existingPath = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = "\(extraPaths):\(existingPath)"
                // Strip session vars that cause the child to think it's a nested session
                for key in ["CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_THREAD_ID",
                            "CLAUDE_CODE_ENTRY_POINT", "CLAUDE_CODE_ENTRYPOINT",
                            "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
                            "CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES",
                            "CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL"] {
                    env.removeValue(forKey: key)
                }
                // Ensure OAuth token is available — CLI needs it to authenticate.
                // When launched from terminal it's in the env; from Finder we read credentials file.
                if env["CLAUDE_CODE_OAUTH_TOKEN"] == nil || env["CLAUDE_CODE_OAUTH_TOKEN"]?.isEmpty == true {
                    let credPath = home.appendingPathComponent(".claude/.credentials.json").path
                    if let data = FileManager.default.contents(atPath: credPath),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let oauth = json["claudeAiOauth"] as? [String: Any],
                       let token = oauth["accessToken"] as? String, !token.isEmpty {
                        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
                        print("[Transcribe] Loaded OAuth token from credentials file")
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
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errOutput = String(data: errData, encoding: .utf8) ?? ""
                    if !errOutput.isEmpty {
                        print("[Transcribe] claude CLI stderr: \(errOutput.prefix(500))")
                    }

                    // Fail on non-zero exit OR if stdout looks like an error response
                    if process.terminationStatus != 0
                        || output.contains("\"type\":\"error\"")
                        || output.contains("authentication_error")
                        || output.contains("Failed to authenticate") {
                        let msg = !errOutput.isEmpty ? errOutput : output
                        continuation.resume(throwing: NSError(domain: "Transcribe", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "claude CLI failed: \(msg.prefix(200))"]))
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

// MARK: - TranscribeStatus Helpers

extension TranscribeStatus {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle:          return "Ready"
        case .listening:     return "Listening..."
        case .transcribing:  return "Transcribing..."
        case .cleaning:      return "Cleaning up..."
        case .injecting:     return "Typing..."
        case .done:          return "Done"
        case .error(let m):  return m
        }
    }
}
