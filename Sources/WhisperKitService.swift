import Foundation
import AVFoundation
import WhisperKit

/// WhisperKit-based speech-to-text engine.
/// Records audio continuously, transcribes chunks in background every ~30s.
/// On stop, transcribes remaining audio and returns full transcript.
/// No live transcript — just a clean result when done.
@MainActor
final class WhisperKitService: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var isModelLoaded = false
    @Published var isLoadingModel = false

    /// Callback when full transcript is ready (on stop)
    var onTranscriptReady: ((String) -> Void)?

    // MARK: - Private

    private var whisperKit: WhisperKit?
    private var isRecording = false
    private var backgroundTask: Task<Void, Never>?

    /// Transcribed text from completed chunks (background processed)
    /// TranscribeService takes these via takeCompletedChunks() for cleanup
    private var completedChunkTexts: [String] = []
    /// Chunks that have been taken by TranscribeService
    private var takenChunkCount: Int = 0
    /// Sample index where last background chunk ended
    private var lastChunkEnd: Int = 0
    /// Background chunk interval in seconds
    private let chunkInterval: Float = 25.0  // transcribe every 25s (Whisper sweet spot is <30s)

    // MARK: - Model Configuration

    static let defaultModel = "base.en"

    // MARK: - Hallucination Filter

    private static let hallucinationPatterns: Set<String> = [
        "thanks for watching", "thank you for watching", "subscribe",
        "like and subscribe", "see you next time",
    ]

    private func isHallucination(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count < 2 { return true }
        if cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" || $0 == "," || $0 == " " }) { return true }
        if Self.hallucinationPatterns.contains(cleaned) { return true }
        let words = cleaned.split(separator: " ")
        if words.count >= 3 && Set(words).count == 1 { return true }
        return false
    }

    // MARK: - Setup

    func setup(model: String = "base.en") async {
        guard whisperKit == nil else { return }
        isLoadingModel = true

        do {
            let config = WhisperKitConfig(
                model: model,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndGPU,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine,
                    prefillCompute: .cpuOnly
                ),
                verbose: false,
                prewarm: true,
                load: true,
                download: true
            )
            whisperKit = try await WhisperKit(config)
            isModelLoaded = true
            print("[WhisperKit] Model '\(model)' loaded successfully")
        } catch {
            print("[WhisperKit] Setup failed: \(error)")
        }

        isLoadingModel = false
    }

    // MARK: - Start / Stop

    func startListening(inputDeviceID: AudioDeviceID? = nil) async {
        guard let whisperKit = whisperKit, !isRecording else {
            DebugLog.log("[WhisperKit] startListening failed — whisperKit nil: \(whisperKit == nil), isRecording: \(isRecording)")
            return
        }

        // Reset
        completedChunkTexts = []
        takenChunkCount = 0
        lastChunkEnd = 0
        isRecording = true
        isListening = true

        do {
            try whisperKit.audioProcessor.startRecordingLive(inputDeviceID: inputDeviceID) { _ in }
            DebugLog.log("[WhisperKit] Recording started (device: \(inputDeviceID.map { String($0) } ?? "default"))")

            // Background task: transcribe chunks every ~25s
            backgroundTask = Task { @MainActor in
                await backgroundChunkLoop()
            }
        } catch {
            DebugLog.log("[WhisperKit] Failed to start recording: \(error)")
            isRecording = false
            isListening = false
        }
    }

    /// Stop recording, transcribe remaining audio, return full transcript
    func stopListening() async -> String {
        guard isRecording else { return "" }

        isRecording = false
        backgroundTask?.cancel()
        backgroundTask = nil

        // Stop recording
        whisperKit?.audioProcessor.stopRecording()
        isListening = false

        // Transcribe only the remaining audio since last background chunk
        // (TranscribeService already has the earlier chunks via takeCompletedChunks)
        let remainingText = await transcribeRemaining()
        let result = (remainingText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        print("[WhisperKit] Remaining chunk: \(result.prefix(100))...")

        if !result.isEmpty {
            onTranscriptReady?(result)
        }

        return result
    }

    /// Synchronous stop (for VoiceService compatibility) — fires callback with result
    func stopListeningSync() {
        guard isRecording else { return }

        isRecording = false
        backgroundTask?.cancel()
        backgroundTask = nil
        whisperKit?.audioProcessor.stopRecording()
        isListening = false

        // Transcribe remaining chunk and fire callback
        Task { @MainActor in
            let remainingText = await transcribeRemaining()
            let result = (remainingText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !result.isEmpty {
                print("[WhisperKit] Remaining chunk: \(result.prefix(100))...")
                onTranscriptReady?(result)
            }
        }
    }

    /// Force-reset all state synchronously — used by endSession() to ensure clean slate
    func forceReset() {
        isRecording = false
        isListening = false
        backgroundTask?.cancel()
        backgroundTask = nil
        whisperKit?.audioProcessor.stopRecording()
        completedChunkTexts = []
        takenChunkCount = 0
        lastChunkEnd = 0
        print("[WhisperKit] Force reset — ready for new session")
    }

    // MARK: - Background Chunk Processing

    /// Every ~25 seconds, transcribe the accumulated audio chunk in background
    private func backgroundChunkLoop() async {
        while isRecording && !Task.isCancelled {
            // Wait for chunk interval
            let sleepNanos = UInt64(chunkInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNanos)
            guard isRecording && !Task.isCancelled else { break }

            guard let whisperKit = whisperKit else { break }
            let currentBuffer = whisperKit.audioProcessor.audioSamples
            let bufferCount = currentBuffer.count
            let newSamples = bufferCount - lastChunkEnd

            // Need at least 1 second of audio
            let newSeconds = Float(newSamples) / Float(WhisperKit.sampleRate)
            guard newSeconds > 1.0 else { continue }

            // Extract chunk with small overlap for context
            let overlapSamples = Int(0.5 * Float(WhisperKit.sampleRate))
            let startIdx = max(0, lastChunkEnd - overlapSamples)
            let chunk = Array(currentBuffer[startIdx..<bufferCount])

            print("[WhisperKit] Background transcribing chunk (\(String(format: "%.1f", newSeconds))s)...")

            if let text = await transcribeAudio(chunk) {
                completedChunkTexts.append(text)
                print("[WhisperKit] Chunk \(completedChunkTexts.count): \"\(text.prefix(60))...\"")
            }

            lastChunkEnd = bufferCount
        }
    }

    /// Transcribe audio remaining after last background chunk
    private func transcribeRemaining() async -> String? {
        guard let whisperKit = whisperKit else { return nil }
        let currentBuffer = whisperKit.audioProcessor.audioSamples
        let bufferCount = currentBuffer.count
        let newSamples = bufferCount - lastChunkEnd

        guard newSamples > Int(0.3 * Float(WhisperKit.sampleRate)) else { return nil }  // at least 0.3s

        let overlapSamples = Int(0.5 * Float(WhisperKit.sampleRate))
        let startIdx = max(0, lastChunkEnd - overlapSamples)
        let chunk = Array(currentBuffer[startIdx..<bufferCount])

        let seconds = Float(newSamples) / Float(WhisperKit.sampleRate)
        print("[WhisperKit] Transcribing remaining audio (\(String(format: "%.1f", seconds))s)...")

        return await transcribeAudio(chunk)
    }

    // MARK: - Core Transcription

    /// Transcribe an audio buffer, filter hallucinations, return clean text
    private func transcribeAudio(_ audioArray: [Float]) async -> String? {
        guard let whisperKit = whisperKit else { return nil }

        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            noSpeechThreshold: 0.4
        )

        do {
            let results: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: audioArray,
                decodeOptions: options
            )

            guard let result = results.first else { return nil }

            // Filter segments
            let cleanTexts = result.segments.compactMap { segment -> String? in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                guard !isHallucination(text) else {
                    print("[WhisperKit] Filtered: '\(text)'")
                    return nil
                }
                // Low confidence filter (very lenient — let cleanup handle the rest)
                guard segment.avgLogprob > -2.5 else {
                    print("[WhisperKit] Low confidence: '\(text)' (logprob: \(segment.avgLogprob))")
                    return nil
                }
                return text
            }

            let combined = cleanTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return combined.isEmpty ? nil : combined
        } catch {
            print("[WhisperKit] Transcription error: \(error)")
            return nil
        }
    }

    // MARK: - Chunk Interface (for TranscribeService)

    /// Take any newly completed chunks that haven't been taken yet.
    /// TranscribeService calls this periodically to clean chunks in background.
    func takeCompletedChunks() -> [String] {
        let newChunks = Array(completedChunkTexts.dropFirst(takenChunkCount))
        takenChunkCount = completedChunkTexts.count
        return newChunks
    }
}
