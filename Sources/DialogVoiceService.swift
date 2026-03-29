import AppKit
import Foundation
import AVFoundation

/// Speaks ELI5 dialog lines using a TTS sidecar server (port 7893).
/// Autoclaw owns the Python TTS process directly — no dependency on SiliconValley Theater app.
/// Uses the /synthesize_dialogue batch endpoint for efficiency — one HTTP call for all lines.
/// Falls back gracefully to text-only if sidecar fails to start.
@MainActor
final class DialogVoiceService: ObservableObject {
    @Published var isSpeaking = false
    @Published var sidecarReady = false

    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var sidecarProcess: Process?
    private var launchTask: Task<Void, Never>?

    private static let sidecarBase = "http://127.0.0.1:7893"
    private static let port = 7893

    // MARK: - Public

    /// Speak dialog lines in sequence using character voices from the TTS sidecar.
    /// Non-blocking — fires and forgets. Cancels any in-progress playback.
    func speak(_ lines: [DialogLine], theme: DialogTheme) {
        playbackTask?.cancel()
        stopPlayback()

        guard !lines.isEmpty else { return }

        playbackTask = Task { @MainActor in
            // Ensure sidecar is up before trying to synthesize
            if !sidecarReady {
                await waitForSidecar(timeout: 10)
            }

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
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            sidecarReady = ok
            return ok
        } catch {
            sidecarReady = false
            return false
        }
    }

    // MARK: - Sidecar Process Management

    /// Launch the TTS Python server directly. Autoclaw owns this process.
    /// Searches for server.py + venv in known locations. Non-blocking — polls for readiness.
    func launchSidecarIfNeeded() {
        // Don't double-launch
        guard launchTask == nil else { return }

        launchTask = Task {
            // Already running?
            if await checkSidecar() {
                DebugLog.log("[TTS] Sidecar already running on port \(Self.port)")
                launchTask = nil
                return
            }

            // Find the TTSSidecar directory
            let searchPaths = [
                Bundle.main.bundlePath + "/../TTSSidecar",
                NSHomeDirectory() + "/Documents/Claude Code/SiliconValley/TTSSidecar",
                NSHomeDirectory() + "/Documents/Claude Code/Autoclaw/TTSSidecar",
            ]

            var sidecarDir: String?
            for path in searchPaths {
                let serverPath = path + "/server.py"
                if FileManager.default.fileExists(atPath: serverPath) {
                    sidecarDir = path
                    break
                }
            }

            guard let dir = sidecarDir else {
                DebugLog.log("[TTS] server.py not found in any search path — voice disabled")
                DebugLog.log("[TTS] Searched: \(searchPaths)")
                launchTask = nil
                return
            }

            let serverScript = dir + "/server.py"
            let venvPython = dir + "/.venv/bin/python3"

            // Prefer venv Python (has all deps installed), fall back to system
            let pythonPath: String
            let args: [String]
            if FileManager.default.fileExists(atPath: venvPython) {
                pythonPath = venvPython
                args = [serverScript, "--port", "\(Self.port)", "--engine", "pocket"]
            } else {
                pythonPath = "/usr/bin/env"
                args = ["python3", serverScript, "--port", "\(Self.port)", "--engine", "pocket"]
            }

            DebugLog.log("[TTS] Starting sidecar: \(pythonPath) \(args.joined(separator: " "))")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: dir)

            // Capture stdout/stderr for debugging
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    for line in text.split(separator: "\n") {
                        DebugLog.log("[TTS-py] \(line)")
                    }
                }
            }

            do {
                try process.run()
                sidecarProcess = process
                DebugLog.log("[TTS] Process started (pid \(process.processIdentifier))")

                // Poll for readiness — model loading can take a while on first run
                for attempt in 1...60 {
                    try? await Task.sleep(for: .seconds(2))

                    if !process.isRunning {
                        DebugLog.log("[TTS] Process exited early (code \(process.terminationStatus))")
                        break
                    }

                    if await checkSidecar() {
                        DebugLog.log("[TTS] Sidecar ready after \(attempt * 2)s")
                        launchTask = nil
                        return
                    }
                }

                DebugLog.log("[TTS] Sidecar did not become ready within 120s")
            } catch {
                DebugLog.log("[TTS] Failed to start sidecar: \(error)")
            }

            launchTask = nil
        }
    }

    /// Wait for the sidecar to become ready (used by speak() to avoid wasting synthesis calls)
    private func waitForSidecar(timeout: Int) async {
        for _ in 0..<timeout {
            if await checkSidecar() { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Kill the sidecar process on app quit
    func stopSidecar() {
        if let process = sidecarProcess, process.isRunning {
            DebugLog.log("[TTS] Stopping sidecar (pid \(process.processIdentifier))")
            process.terminate()
        }
        sidecarProcess = nil
        sidecarReady = false
        launchTask?.cancel()
        launchTask = nil
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
                DebugLog.log("[TTS] Sidecar returned non-200 or bad JSON")
                return Array(repeating: nil, count: turns.count)
            }

            return audioList.map { $0.flatMap { Data(base64Encoded: $0) } }
        } catch {
            DebugLog.log("[TTS] Sidecar unreachable: \(error.localizedDescription)")
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
                DebugLog.log("[TTS] Playback error: \(error)")
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
