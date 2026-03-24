import Foundation
import Combine

// MARK: - Transcribe Service

/// Orchestrates the voice-to-cursor pipeline:
/// Mic (VoiceService) → Qwen cleanup (OllamaService) → Type at cursor (CursorInjector)
@MainActor
final class TranscribeService: ObservableObject {
    @Published var status: TranscribeStatus = .idle
    @Published var rawText = ""
    @Published var cleanText = ""

    private let voiceService: VoiceService
    private let ollamaService: OllamaService
    private var cancellables = Set<AnyCancellable>()
    private var previousOnTranscriptReady: ((String) -> Void)?

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
        voiceService.stopListening()

        // If we have raw text but haven't processed yet, process it now
        if status == .listening && !rawText.isEmpty {
            Task { @MainActor in
                await handleTranscript(rawText)
            }
        } else {
            cleanup()
        }
    }

    // MARK: - Private

    private func handleTranscript(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .idle
            cleanup()
            return
        }

        rawText = text
        status = .cleaning
        print("[Transcribe] Cleaning: \(text.prefix(80))...")

        do {
            // Check Ollama availability first
            let available = await ollamaService.isAvailable()
            guard available else {
                // Fallback: use raw text without cleanup
                print("[Transcribe] Ollama not available, using raw text")
                cleanText = text
                await injectText(text)
                return
            }

            let cleaned = try await ollamaService.generate(
                prompt: text,
                system: Self.cleanupSystemPrompt
            )
            cleanText = cleaned
            print("[Transcribe] Cleaned: \(cleaned.prefix(80))...")
            await injectText(cleaned)
        } catch {
            print("[Transcribe] Cleanup error: \(error)")
            // Fallback: inject raw text
            cleanText = text
            await injectText(text)
        }
    }

    private func injectText(_ text: String) async {
        status = .injecting
        await CursorInjector.type(text)
        status = .done
        print("[Transcribe] Injected at cursor")

        // Auto-reset after a short delay
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        if status == .done {
            status = .idle
            rawText = ""
            cleanText = ""
        }
        cleanup()
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
