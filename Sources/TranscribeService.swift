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
            if !cleaned.isEmpty { return cleaned }
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

    // MARK: - Screen Context

    /// Capture screenshot via screencapture CLI, then OCR it for enhance context
    private func captureScreenContext() -> String? {
        let tmpPath = NSTemporaryDirectory() + "autoclaw_enhance_\(ProcessInfo.processInfo.processIdentifier).png"

        // Use screencapture CLI (works on all macOS versions)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-C", tmpPath]  // -x no sound, -C capture cursor
        try? process.run()
        process.waitUntilExit()

        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        // Load as CGImage
        guard let dataProvider = CGDataProvider(url: URL(fileURLWithPath: tmpPath) as CFURL),
              let cgImage = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }

        // Get cursor position for proximity ranking
        let cursorLocation = NSEvent.mouseLocation
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

        // Run OCR
        let observations = ScreenOCR.recognizeText(
            in: cgImage,
            cursorLocation: cursorLocation,
            imageSize: screenSize
        )

        return ScreenOCR.buildContext(from: observations, maxLength: 800)
    }

    // MARK: - Smart Enhancement

    private func enhanceWithModel(text: String, app: String) async {
        let provider = AppSettings.shared.enhanceProvider
        guard provider != .none else { return }

        isEnhancing = true
        enhancedText = ""

        // Capture what's on screen for context
        let screenContext = captureScreenContext()

        let appContext: String
        switch app.lowercased() {
        case let a where a.contains("claude"):
            appContext = "The user is on Claude (AI assistant). Improve this as a clear, specific AI prompt with good structure."
        case let a where a.contains("gmail") || a.contains("mail"):
            appContext = "The user is composing an email. Polish this into a professional, clear email message."
        case let a where a.contains("freepik") || a.contains("midjourney") || a.contains("dall"):
            appContext = "The user is on an image generation tool. Transform this into a detailed, effective image generation prompt."
        case let a where a.contains("slack") || a.contains("discord") || a.contains("teams"):
            appContext = "The user is in a messaging app. Keep casual but clear and well-structured."
        case let a where a.contains("notion") || a.contains("docs") || a.contains("word"):
            appContext = "The user is writing a document. Polish for clarity, grammar, and professional tone."
        case let a where a.contains("twitter") || a.contains("x.com") || a.contains("linkedin"):
            appContext = "The user is on social media. Make this punchy, engaging, and platform-appropriate."
        case let a where a.contains("code") || a.contains("xcode") || a.contains("terminal") || a.contains("iterm"):
            appContext = "The user is in a code editor or terminal. Format as appropriate code comment or commit message."
        default:
            appContext = "Improve this text for clarity and effectiveness. Keep the original intent."
        }

        var screenSection = ""
        if let ctx = screenContext {
            screenSection = """

            What's visible on the user's screen right now:
            \(ctx)

            Use this screen context to make the enhanced text more relevant. For example, if they're replying to an email, \
            match the tone and reference what's being discussed. If they're in a code review, use technical language.
            """
        }

        let prompt = """
        You are a smart writing assistant. The user just dictated the following text via voice:

        "\(text)"

        Context: \(appContext)
        Active app: \(app)
        \(screenSection)

        Return ONLY the improved version. No explanations, no quotes, no prefixes. Just the enhanced text.
        """

        do {
            let result = try await callClaudeCLI(prompt: prompt, model: provider.modelFlag)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && cleaned != text {
                enhancedText = cleaned
                print("[Transcribe] Enhanced: \(cleaned.prefix(80))...")
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
                env["PATH"] = "\(homePath)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
                // Keep CLAUDE_CODE_OAUTH_TOKEN (needed for auth) but strip session vars
                // that cause the child to think it's a nested session
                env.removeValue(forKey: "CLAUDE_CODE_SESSION_ID")
                env.removeValue(forKey: "CLAUDE_CODE_THREAD_ID")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRY_POINT")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                env.removeValue(forKey: "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST")
                env.removeValue(forKey: "CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES")
                env.removeValue(forKey: "CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL")
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

                    if process.terminationStatus != 0 && output.isEmpty {
                        continuation.resume(throwing: NSError(domain: "Transcribe", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "claude CLI failed: \(errOutput.prefix(200))"]))
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
