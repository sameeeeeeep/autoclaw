import Foundation
import WhisperKit

@main
struct WhisperTest {
    static func main() async {
        print("=== WhisperKit Transcription Test ===\n")

        // Init WhisperKit
        print("[1/3] Loading WhisperKit (base.en)...")
        let config = WhisperKitConfig(
            model: "base.en",
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )

        guard let whisperKit = try? await WhisperKit(config) else {
            print("ERROR: Failed to load WhisperKit")
            return
        }
        print("[1/3] Model loaded!\n")

        // Test files
        let testFiles = [
            ("/tmp/tw1.wav", "I want to update the readme file and fix the build script for the project"),
            ("/tmp/tw2.wav", "Hey can you check if the new feature works and let me know by end of day thanks"),
        ]

        for (i, (path, expected)) in testFiles.enumerated() {
            print("[Test \(i+1)] Expected: \"\(expected)\"")

            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                skipSpecialTokens: true,
                suppressBlank: true,
                compressionRatioThreshold: 2.4,
                noSpeechThreshold: 0.6
            )

            do {
                let results = try await whisperKit.transcribe(
                    audioPath: path,
                    decodeOptions: options
                )
                if let result = results.first {
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[Test \(i+1)] Got:      \"\(text)\"")

                    // Check segments
                    for seg in result.segments {
                        print("  segment: \"\(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))\" (logprob: \(String(format: "%.2f", seg.avgLogprob)))")
                    }

                    // Simple accuracy check
                    let match = text.lowercased().contains("update") || text.lowercased().contains("readme") || text.lowercased().contains("feature") || text.lowercased().contains("check")
                    print("[Test \(i+1)] PASS: \(match ? "YES" : "NO")")
                } else {
                    print("[Test \(i+1)] ERROR: No results")
                }
            } catch {
                print("[Test \(i+1)] ERROR: \(error)")
            }
            print()
        }

        print("=== Test Complete ===")
    }
}
