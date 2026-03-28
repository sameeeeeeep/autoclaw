import Foundation
import WhisperKit
import AVFoundation

// MARK: - Hallucination Filter (copied from WhisperKitService)

let hallucinationPatterns: Set<String> = [
    "thanks for watching", "thank you for watching", "subscribe",
    "like and subscribe", "see you next time",
]

func isHallucination(_ text: String) -> Bool {
    let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.count < 2 { return true }
    if cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" || $0 == "," || $0 == " " }) { return true }
    if hallucinationPatterns.contains(cleaned) { return true }
    let words = cleaned.split(separator: " ")
    if words.count >= 3 && Set(words).count == 1 { return true }
    return false
}

/// Filter segments exactly like WhisperKitService.transcribeAudio()
func filterSegments(_ result: TranscriptionResult) -> String? {
    let cleanTexts = result.segments.compactMap { segment -> String? in
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard !isHallucination(text) else {
            print("  [FILTERED hallucination] '\(text)'")
            return nil
        }
        guard segment.avgLogprob > -2.5 else {
            print("  [FILTERED low confidence] '\(text)' (logprob: \(String(format: "%.2f", segment.avgLogprob)))")
            return nil
        }
        return text
    }
    let combined = cleanTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return combined.isEmpty ? nil : combined
}

// MARK: - Audio Loading

func loadAudioSamples(from path: String) -> [Float]? {
    let url = URL(fileURLWithPath: path)
    guard let file = try? AVAudioFile(forReading: url) else {
        print("ERROR: Can't open audio file at \(path)")
        return nil
    }

    // Convert to 16kHz mono Float32 (WhisperKit format)
    let targetSampleRate: Double = 16000
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
        print("ERROR: Can't create target format")
        return nil
    }

    guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
        print("ERROR: Can't create converter")
        return nil
    }

    let frameCount = AVAudioFrameCount(Double(file.length) * targetSampleRate / file.processingFormat.sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        print("ERROR: Can't create buffer")
        return nil
    }

    var error: NSError?
    converter.convert(to: buffer, error: &error) { inNumPackets, outStatus in
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inNumPackets)!
        do {
            try file.read(into: inputBuffer, frameCount: inNumPackets)
            outStatus.pointee = .haveData
            return inputBuffer
        } catch {
            outStatus.pointee = .endOfStream
            return nil
        }
    }

    if let error = error {
        print("ERROR: Conversion failed: \(error)")
        return nil
    }

    guard let channelData = buffer.floatChannelData else { return nil }
    return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
}

// MARK: - Pipeline Simulation

@main
struct WhisperTest {
    static func main() async {
        print("=" * 60)
        print("AUTOCLAW TRANSCRIPTION PIPELINE TEST")
        print("=" * 60)

        let testAudioPath = "/tmp/autoclaw_pipeline_test.aiff"

        // Check test audio exists
        guard FileManager.default.fileExists(atPath: testAudioPath) else {
            print("\nERROR: No test audio at \(testAudioPath)")
            print("Generate it with: say -o \(testAudioPath) --rate=180 \"your text here\"")
            return
        }

        // 1. Load WhisperKit
        print("\n[STEP 1] Loading WhisperKit (base.en)...")
        let config = WhisperKitConfig(
            model: "base.en",
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

        guard let whisperKit = try? await WhisperKit(config) else {
            print("ERROR: Failed to load WhisperKit")
            return
        }
        print("[STEP 1] Model loaded!\n")

        // 2. Load audio samples
        print("[STEP 2] Loading audio samples...")
        guard let allSamples = loadAudioSamples(from: testAudioPath) else {
            print("ERROR: Failed to load audio samples")
            return
        }
        let sampleRate = 16000
        let totalSeconds = Float(allSamples.count) / Float(sampleRate)
        print("[STEP 2] Loaded \(allSamples.count) samples (\(String(format: "%.1f", totalSeconds))s)\n")

        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: "en",
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            noSpeechThreshold: 0.4
        )

        // ============================================================
        // TEST A: Full audio transcription (baseline — what we SHOULD get)
        // ============================================================
        print("-" * 60)
        print("TEST A: BASELINE — Transcribe full audio at once")
        print("-" * 60)

        if let results = try? await whisperKit.transcribe(audioArray: allSamples, decodeOptions: decodeOptions),
           let result = results.first {
            let baseline = filterSegments(result)
            print("Baseline text: \"\(baseline ?? "(empty)")\"")
            print("Baseline segments: \(result.segments.count)")
            print()
        }

        // ============================================================
        // TEST B: Chunked pipeline — simulate WhisperKit backgroundChunkLoop
        // ============================================================
        print("-" * 60)
        print("TEST B: CHUNKED PIPELINE — Simulate 25s chunks like real app")
        print("-" * 60)

        let chunkInterval = 25.0  // seconds
        let overlapSeconds: Float = 0.5
        let overlapSamples = Int(overlapSeconds * Float(sampleRate))

        var completedChunkTexts: [String] = []  // WhisperKit's accumulator
        var lastChunkEnd = 0  // sample index
        var chunkIndex = 0

        // Simulate backgroundChunkLoop
        while true {
            let nextChunkEnd = min(allSamples.count, lastChunkEnd + Int(chunkInterval) * sampleRate)
            let newSamples = nextChunkEnd - lastChunkEnd

            if Float(newSamples) / Float(sampleRate) < 1.0 { break }  // < 1s, stop chunking

            let startIdx = max(0, lastChunkEnd - overlapSamples)
            let chunk = Array(allSamples[startIdx..<nextChunkEnd])
            let chunkSeconds = Float(chunk.count) / Float(sampleRate)

            chunkIndex += 1
            print("\n  Chunk \(chunkIndex): samples[\(startIdx)..\(nextChunkEnd)] (\(String(format: "%.1f", chunkSeconds))s)")

            if let results = try? await whisperKit.transcribe(audioArray: chunk, decodeOptions: decodeOptions),
               let result = results.first,
               let text = filterSegments(result) {
                completedChunkTexts.append(text)
                print("  Chunk \(chunkIndex) text: \"\(text)\"")
            } else {
                print("  Chunk \(chunkIndex): EMPTY (no transcription result)")
            }

            lastChunkEnd = nextChunkEnd

            // If we've consumed all samples, break
            if nextChunkEnd >= allSamples.count { break }
        }

        // Simulate transcribeRemaining (audio after last chunk)
        let remainingSamples = allSamples.count - lastChunkEnd
        var remainingText: String? = nil

        if remainingSamples > Int(0.3 * Float(sampleRate)) {
            let startIdx = max(0, lastChunkEnd - overlapSamples)
            let remaining = Array(allSamples[startIdx...])
            let remSeconds = Float(remaining.count) / Float(sampleRate)

            print("\n  Remaining: samples[\(startIdx)..\(allSamples.count)] (\(String(format: "%.1f", remSeconds))s)")

            if let results = try? await whisperKit.transcribe(audioArray: remaining, decodeOptions: decodeOptions),
               let result = results.first {
                remainingText = filterSegments(result)
                print("  Remaining text: \"\(remainingText ?? "(empty)")\"")
            }
        } else {
            print("\n  Remaining: <0.3s, skipped")
        }

        // Simulate TranscribeService.stop() — combine all chunks
        var allChunks = completedChunkTexts
        if let rem = remainingText, !rem.isEmpty {
            allChunks.append(rem)
        }

        let finalText = allChunks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        print("\n" + "=" * 60)
        print("PIPELINE RESULT")
        print("=" * 60)
        print("Chunks produced: \(completedChunkTexts.count)")
        print("Remaining chunk: \(remainingText != nil ? "yes" : "no")")
        print("Total chunks combined: \(allChunks.count)")
        print()
        print("Final text (\(finalText.count) chars):")
        print("\"\(finalText)\"")
        print()

        // ============================================================
        // TEST C: Simulate the RACE CONDITION
        // ============================================================
        print("-" * 60)
        print("TEST C: RACE CONDITION — What happens when drain misses a chunk")
        print("-" * 60)

        // Simulate: TranscribeService pulls chunks with a lag
        // WhisperKit produces chunks at 25s, 50s
        // TranscribeService pulls at 25s (gets nothing — WhisperKit still transcribing)
        // TranscribeService pulls at 50s (gets chunk 1, WhisperKit still on chunk 2)
        // User stops at 55s
        // WITHOUT drain: chunk 2 is lost, only remaining (50-55s) captured
        // WITH drain: chunk 2 is captured before stop

        var wk_completed: [String] = []  // WhisperKit's completedChunkTexts
        var wk_taken = 0                  // takenChunkCount
        var ts_cleaned: [String] = []     // TranscribeService's cleanedChunks

        // t=25s: WhisperKit transcribes chunk 1
        wk_completed.append("chunk one from zero to twenty five seconds")

        // t=25s: TranscribeService tries to pull — but in real app, WhisperKit is still
        //        transcribing so it gets nothing. Simulating the lag:
        let pull1 = Array(wk_completed.dropFirst(wk_taken))
        // In reality, pull happens WHILE WhisperKit is transcribing, so it gets the chunk
        // that was ALREADY there. The race is when both fire at the same 25s mark.
        // Let's simulate the worst case: pull fires BEFORE WhisperKit finishes:
        // ts pulls: gets nothing (wk_taken = 0, wk_completed = empty at that moment)
        // For this test, simulate pull gets chunk 1:
        wk_taken = wk_completed.count
        ts_cleaned.append(contentsOf: pull1)
        print("  t=25s: TranscribeService pulled \(pull1.count) chunk(s)")

        // t=50s: WhisperKit transcribes chunk 2
        wk_completed.append("chunk two from twenty five to fifty seconds")

        // t=50s: TranscribeService pulls — gets chunk 2
        let pull2 = Array(wk_completed.dropFirst(wk_taken))
        // WORST CASE: pull fires before chunk 2 is added → gets nothing
        // Simulating worst case:
        print("  t=50s: WhisperKit produced chunk 2, but TranscribeService already pulled (race)")
        // Don't update wk_taken — chunk 2 is unclaimed

        // t=55s: User stops
        print("  t=55s: User stops")

        // WITHOUT drain fix:
        let withoutDrain = ts_cleaned.joined(separator: " ") + " [remaining 50-55s text]"
        print("\n  WITHOUT drain: \"\(withoutDrain)\"")
        print("  LOST: chunk 2! (\(wk_completed[1]))")

        // WITH drain fix:
        let drainedChunks = Array(wk_completed.dropFirst(wk_taken))
        ts_cleaned.append(contentsOf: drainedChunks)
        wk_taken = wk_completed.count
        let withDrain = ts_cleaned.joined(separator: " ") + " [remaining 50-55s text]"
        print("\n  WITH drain: \"\(withDrain)\"")
        print("  All chunks captured!")

        print("\n" + "=" * 60)
        print("TEST COMPLETE")
        print("=" * 60)
    }
}

// Helper for string repetition
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
