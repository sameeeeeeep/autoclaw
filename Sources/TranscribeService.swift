import Foundation
import Combine
import AppKit

// MARK: - Transcribe Service

/// Orchestrates the voice-to-cursor pipeline:
/// Record → background chunk transcription + cleanup → on stop, only last chunk left → show clean text → enhance
///
/// Background loop every ~25s: transcribe chunk → clean it → store.
/// On stop: transcribe remaining chunk → clean it → combine all cleaned chunks → inject → enhance.
/// User sees "Listening..." while recording, then clean text immediately when they stop.
@MainActor
final class TranscribeService: ObservableObject {
    @Published var status: TranscribeStatus = .idle
    @Published var rawText = ""
    @Published var cleanText = ""
    @Published var enhancedText = ""
    @Published var isEnhancing = false

    private let voiceService: VoiceService
    private let ollamaService: OllamaService

    /// The app user was in when they started transcribing
    var activeApp: String = ""

    /// Cleaned chunks accumulated during background processing
    private var cleanedChunks: [String] = []
    /// Background processing task
    private var backgroundTask: Task<Void, Never>?

    private static let cleanupSystemPrompt = """
    Clean up this spoken text for typing. Remove filler words (um, uh, like, you know, so, basically, actually). \
    Fix grammar and punctuation. Keep the original meaning and tone. Do not add or change content. \
    Return ONLY the cleaned text, nothing else.
    """

    /// How often to transcribe + clean a chunk (seconds)
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
        cleanedChunks = []
        rawText = ""
        cleanText = ""
        enhancedText = ""
        isEnhancing = false
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
        cleanedChunks = []
        status = .listening

        DebugLog.log("[Transcribe] Starting recording (backend: \(voiceService.activeBackend.rawValue), whisperKit loaded: \(voiceService.whisperKitService.isModelLoaded))")
        voiceService.startListening()

        // Start background chunk processing (transcribe + clean every ~25s)
        startBackgroundProcessing()
    }

    /// Stop recording → transcribe + clean last chunk → combine → inject → enhance
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
            // 1. Stop recording and get remaining audio transcribed
            DebugLog.log("[Transcribe] Calling stopAndTranscribe...")
            let lastChunkRaw = await voiceService.stopAndTranscribe()
            let trimmed = lastChunkRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.log("[Transcribe] Raw from WhisperKit (\(trimmed.count) chars): \(trimmed.prefix(200))")

            // 2. Clean the last chunk (only thing that needs processing at stop time)
            if !trimmed.isEmpty {
                DebugLog.log("[Transcribe] Cleaning last chunk...")
                let lastCleaned = await cleanupText(trimmed)
                cleanedChunks.append(lastCleaned)
                DebugLog.log("[Transcribe] Cleaned: \(lastCleaned.prefix(200))")
            }

            // 3. Combine all cleaned chunks
            let fullClean = cleanedChunks
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !fullClean.isEmpty else {
                DebugLog.log("[Transcribe] Empty result after cleaning")
                status = .idle
                return
            }

            cleanText = fullClean
            rawText = fullClean
            DebugLog.log("[Transcribe] Final clean text (\(cleanedChunks.count) chunks): \(fullClean.prefix(200))")

            // 4. Inject at cursor
            await injectText(fullClean)

            // 5. Smart enhance in background
            let app = activeApp
            Task { @MainActor in
                await enhanceWithModel(text: fullClean, app: app)
            }
        }
    }

    // MARK: - Background Chunk Processing

    /// Runs in background: every ~25s, asks WhisperKit for completed chunk text and cleans it
    private func startBackgroundProcessing() {
        backgroundTask = Task { @MainActor in
            while !Task.isCancelled {
                // Wait for chunk interval
                try? await Task.sleep(nanoseconds: UInt64(chunkInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Get any completed chunks from WhisperKit
                let whisperKit = voiceService.whisperKitService
                let chunks = whisperKit.takeCompletedChunks()

                for rawChunk in chunks {
                    let trimmed = rawChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    print("[Transcribe] Background cleaning chunk: \(trimmed.prefix(60))...")
                    let cleaned = await cleanupText(trimmed)
                    cleanedChunks.append(cleaned)
                    print("[Transcribe] Chunk cleaned (\(cleanedChunks.count) total): \(cleaned.prefix(60))...")
                }
            }
        }
    }

    // MARK: - Cleanup (shared by background + final)

    /// Clean text using configured provider. Used for both background chunks and final chunk.
    private func cleanupText(_ text: String) async -> String {
        let provider = AppSettings.shared.cleanupProvider

        switch provider {
        case .none:
            return text
        case .qwen:
            return await cleanupWithQwen(text)
        case .haiku:
            return await cleanupWithHaiku(text)
        }
    }

    private func cleanupWithQwen(_ text: String) async -> String {
        do {
            let result = try await ollamaService.generate(
                prompt: text,
                system: Self.cleanupSystemPrompt
            )
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        } catch {
            print("[Transcribe] Qwen cleanup failed: \(error)")
        }
        return text
    }

    private func cleanupWithHaiku(_ text: String) async -> String {
        let prompt = """
        Clean up this spoken text for typing. Remove filler words (um, uh, like, you know, so, basically, actually). \
        Fix grammar and punctuation. Keep the original meaning and tone. Do not add or change content. \
        Return ONLY the cleaned text, nothing else.

        "\(text)"
        """

        do {
            let result = try await callClaudeCLI(prompt: prompt, model: "haiku")
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !cleaned.contains("\"type\":\"error\"") && !cleaned.hasPrefix("{") {
                return cleaned
            }
            print("[Transcribe] Haiku cleanup returned error, using raw text")
        } catch {
            print("[Transcribe] Haiku cleanup failed: \(error)")
        }
        return text
    }

    // MARK: - Injection

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

        let prompt = """
        Rewrite this dictated text to be better. Keep the user's voice and meaning. \
        Make it sharper and clearer. If it's already good, return it mostly as-is. \
        Tone: \(appContext). Active app: \(app). \
        Return ONLY the improved text, nothing else.

        "\(text)"
        """

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

    private func callClaudeCLI(prompt: String, model: String = "haiku") async throws -> String {
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
                process.arguments = ["--model", model, "-p", prompt, "--output-format", "text", "--dangerously-skip-permissions"]

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
