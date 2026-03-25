import Foundation
import Combine

// MARK: - Transcribe Service

/// Orchestrates the voice-to-cursor pipeline:
/// Mic (VoiceService) → Type at cursor (CursorInjector) → Haiku enhance (background)
@MainActor
final class TranscribeService: ObservableObject {
    @Published var status: TranscribeStatus = .idle
    @Published var rawText = ""
    @Published var cleanText = ""
    @Published var enhancedText = ""       // Smart suggestion from Haiku
    @Published var isEnhancing = false     // True while Haiku is thinking

    private let voiceService: VoiceService
    private let ollamaService: OllamaService
    private var cancellables = Set<AnyCancellable>()
    private var previousOnTranscriptReady: ((String) -> Void)?

    /// The app user was in when they started transcribing — used for context-aware enhancement
    var activeApp: String = ""

    private static let cleanupSystemPrompt = """
    Clean up this spoken text for typing. Remove filler words (um, uh, like, you know, so, basically, actually). \
    Fix grammar and punctuation. Keep the original meaning and tone. Do not add or change content. \
    Return ONLY the cleaned text, nothing else.
    """

    init(voiceService: VoiceService, ollamaService: OllamaService) {
        self.voiceService = voiceService
        self.ollamaService = ollamaService
    }

    // MARK: - Public

    /// Enhance clipboard text without voice — same Haiku pipeline, clipboard trigger
    func enhanceClipboard(_ text: String, app: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        rawText = trimmed
        cleanText = trimmed
        enhancedText = ""
        activeApp = app
        status = .done  // Skip listening/injecting — text is already in the field

        print("[Transcribe] Enhancing clipboard: \(trimmed.prefix(60))... for \(app)")

        Task { @MainActor in
            await enhanceWithHaiku(text: trimmed, app: app)
        }
    }

    func start() {
        guard status == .idle || status == .done || status.isError else { return }

        rawText = ""
        cleanText = ""
        status = .listening

        // Stream live partial transcript for display
        voiceService.$currentTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self, self.status == .listening else { return }
                self.rawText = text
            }
            .store(in: &cancellables)

        // Save existing callback and replace with transcribe handler
        previousOnTranscriptReady = voiceService.onTranscriptReady
        voiceService.onTranscriptReady = { [weak self] text in
            Task { @MainActor in
                await self?.handleTranscript(text)
            }
        }

        voiceService.startListening()
        print("[Transcribe] Started listening")
    }

    func stop() {
        // Grab the text BEFORE stopping (stopListening may clear state)
        let textToProcess = rawText.isEmpty ? voiceService.currentTranscript : rawText
        let wasListening = status == .listening

        // Temporarily remove our callback to prevent double-processing
        voiceService.onTranscriptReady = nil
        voiceService.stopListening()

        // Process whatever text we captured
        if wasListening && !textToProcess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { @MainActor in
                await handleTranscript(textToProcess)
            }
        } else {
            status = .idle
            cleanup()
        }
    }

    // MARK: - Private

    private func handleTranscript(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[Transcribe] Empty text, skipping")
            status = .idle
            cleanup()
            return
        }

        rawText = trimmed
        cleanText = trimmed
        print("[Transcribe] Got transcript: \(trimmed.prefix(100))...")

        // 1. Inject raw text immediately — no delay
        await injectText(trimmed)

        // 2. Fire Haiku enhancement in background (non-blocking)
        let app = activeApp
        Task { @MainActor in
            await enhanceWithHaiku(text: trimmed, app: app)
        }
    }

    private func injectText(_ text: String) async {
        status = .injecting
        print("[Transcribe] Injecting at cursor: \(text.prefix(60))...")
        await CursorInjector.type(text)
        status = .done
        print("[Transcribe] Injected successfully")
        cleanup()
    }

    /// Inject the enhanced text at cursor, replacing what's there
    func injectEnhanced() async {
        guard !enhancedText.isEmpty else { return }
        status = .injecting
        // Select all text in the current field (Cmd+A) then paste replacement
        await CursorInjector.selectAllAndReplace(enhancedText)
        cleanText = enhancedText
        status = .done
        print("[Transcribe] Injected enhanced text")
    }

    // MARK: - Haiku Enhancement

    private func enhanceWithHaiku(text: String, app: String) async {
        isEnhancing = true
        enhancedText = ""

        let appContext: String
        switch app.lowercased() {
        case let a where a.contains("claude"):
            appContext = "The user is on Claude (AI assistant). Improve this as a clear, specific AI prompt with good structure."
        case let a where a.contains("gmail") || a.contains("mail"):
            appContext = "The user is composing an email. Polish this into a professional, clear email message."
        case let a where a.contains("freepik") || a.contains("midjourney") || a.contains("dall"):
            appContext = "The user is on an image generation tool. Transform this into a detailed, effective image generation prompt with style, lighting, and composition details."
        case let a where a.contains("slack") || a.contains("discord") || a.contains("teams"):
            appContext = "The user is in a messaging app. Keep the tone casual but make the message clear and well-structured."
        case let a where a.contains("notion") || a.contains("docs") || a.contains("word"):
            appContext = "The user is writing a document. Polish the text for clarity, grammar, and professional tone."
        case let a where a.contains("twitter") || a.contains("x.com") || a.contains("linkedin"):
            appContext = "The user is on social media. Make this punchy, engaging, and platform-appropriate."
        default:
            appContext = "Improve this text for clarity and effectiveness. Keep the original intent."
        }

        let prompt = """
        You are a smart writing assistant. The user just dictated the following text via voice:

        "\(text)"

        Context: \(appContext)

        Return ONLY the improved version. No explanations, no quotes, no prefixes. Just the enhanced text.
        """

        do {
            let result = try await callHaikuCLI(prompt: prompt)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && cleaned != text {
                enhancedText = cleaned
                print("[Transcribe] Haiku enhanced: \(cleaned.prefix(80))...")
            } else {
                print("[Transcribe] Haiku returned same text, no enhancement")
            }
        } catch {
            print("[Transcribe] Haiku enhancement failed: \(error)")
        }

        isEnhancing = false
    }

    private func callHaikuCLI(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Find claude CLI
                let home = FileManager.default.homeDirectoryForCurrentUser
                let localBin = home.appendingPathComponent(".local/bin/claude").path
                let candidates = [localBin, "/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
                guard let cliPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    continuation.resume(throwing: NSError(domain: "Transcribe", code: 1, userInfo: [NSLocalizedDescriptionKey: "claude CLI not found"]))
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = ["--model", "haiku", "-p", prompt, "--output-format", "text", "--dangerously-skip-permissions"]

                // Clean env
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDE_CODE_SESSION_ID")
                env.removeValue(forKey: "CLAUDE_CODE_THREAD_ID")
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func cleanup() {
        cancellables.removeAll()
        // Restore original voice callback
        if let previous = previousOnTranscriptReady {
            voiceService.onTranscriptReady = previous
            previousOnTranscriptReady = nil
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
        case .idle:        return "Ready"
        case .listening:   return "Listening…"
        case .cleaning:    return "Cleaning up…"
        case .injecting:   return "Typing…"
        case .done:        return "Done"
        case .error(let m): return m
        }
    }
}
