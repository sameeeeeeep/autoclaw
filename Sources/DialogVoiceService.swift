import Foundation
import AVFoundation

/// Speaks ELI5 dialog lines using the SiliconValley Theater TTS sidecar (port 7893).
/// Uses the /synthesize_dialogue batch endpoint for efficiency — one HTTP call for both lines.
/// Falls back gracefully to silence if sidecar isn't running.
@MainActor
final class DialogVoiceService: ObservableObject {
    @Published var isSpeaking = false

    private var player: AVAudioPlayer?
    private var playbackQueue: [Data] = []
    private var playbackTask: Task<Void, Never>?

    private static let sidecarBase = "http://127.0.0.1:7893"

    // MARK: - Public

    /// Speak dialog lines in sequence using character voices from the TTS sidecar.
    /// Non-blocking — fires and forgets. Cancels any in-progress playback.
    func speak(_ lines: [DialogLine], theme: DialogTheme) {
        playbackTask?.cancel()
        stopPlayback()

        guard !lines.isEmpty else { return }

        playbackTask = Task { @MainActor in
            // Map dialog lines to TTS turns with correct voice IDs
            let turns: [(text: String, voiceID: String)] = lines.map { line in
                let voiceID = line.character == theme.char1 ? theme.voice1 : theme.voice2
                return (text: line.line, voiceID: voiceID)
            }

            // Batch synthesize via sidecar
            let audioChunks = await synthesizeDialogue(turns: turns)

            guard !Task.isCancelled else { return }

            // Play each chunk sequentially
            isSpeaking = true
            for chunk in audioChunks {
                guard !Task.isCancelled else { break }
                guard let data = chunk else { continue }
                await playAndWait(data: data)
            }
            isSpeaking = false
        }
    }

    /// Stop any in-progress playback
    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        stopPlayback()
    }

    /// Check if the TTS sidecar is reachable
    func checkSidecar() async -> Bool {
        guard let url = URL(string: "\(Self.sidecarBase)/health") else { return false }
        do {
            let (_, resp) = try await URLSession.shared.data(from: url)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Synthesis

    /// Call the sidecar's /synthesize_dialogue batch endpoint.
    /// Returns an array of optional WAV Data (nil for failed turns).
    private func synthesizeDialogue(turns: [(text: String, voiceID: String)]) async -> [Data?] {
        guard let url = URL(string: "\(Self.sidecarBase)/synthesize_dialogue") else {
            return Array(repeating: nil, count: turns.count)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let turnsPayload = turns.map { ["text": $0.text, "voice_id": $0.voiceID] }
        let payload: [String: Any] = ["turns": turnsPayload, "speed": 1.0]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioList = json["audio"] as? [String?]
            else {
                DebugLog.log("[DialogVoice] Sidecar returned non-200 or bad JSON")
                return Array(repeating: nil, count: turns.count)
            }

            return audioList.map { $0.flatMap { Data(base64Encoded: $0) } }
        } catch {
            DebugLog.log("[DialogVoice] Sidecar unreachable: \(error.localizedDescription)")
            return Array(repeating: nil, count: turns.count)
        }
    }

    // MARK: - Playback

    /// Play WAV data and wait for it to finish (async bridge over AVAudioPlayer delegate).
    private func playAndWait(data: Data) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                let audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer.volume = 0.8

                let delegate = PlaybackDelegate {
                    cont.resume()
                }
                audioPlayer.delegate = delegate
                // Prevent delegate from being deallocated
                objc_setAssociatedObject(audioPlayer, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

                audioPlayer.prepareToPlay()
                audioPlayer.play()
                self.player = audioPlayer
            } catch {
                DebugLog.log("[DialogVoice] Playback error: \(error)")
                cont.resume()
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isSpeaking = false
    }
}

// MARK: - AVAudioPlayer Delegate

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinished()
    }
}
