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
    /// Index of the line currently being spoken within the full sessionDialog array.
    /// -1 when not speaking. TheaterPIPView uses this to sync bubbles with audio.
    @Published var currentLineIndex: Int = -1
    /// True when playing filler content between real dialogs
    @Published var isPlayingFiller = false

    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var sidecarProcess: Process?
    private var launchTask: Task<Void, Never>?

    /// Queued dialog — buffered when new dialog arrives mid-playback.
    /// Played automatically after the current batch finishes.
    private var dialogQueue: [(lines: [DialogLine], theme: DialogTheme, baseIndex: Int)] = []
    private var isPlayingBatch = false
    private var lastColdOpenIndex: Int = -1
    private var fillerTimer: Timer?
    private var loadedFillers: [String: [[DialogLine]]] = [:]  // themeId -> array of filler conversations

    private static let sidecarBase = "http://127.0.0.1:7893"
    private static let port = 7893

    // MARK: - Public

    /// Speak dialog lines in sequence using character voices from the TTS sidecar.
    /// If currently speaking, queues the new dialog and injects a cold open to bridge the gap.
    /// Non-blocking — fires and forgets.
    /// - Parameter baseIndex: index of the first line in the full sessionDialog array (for bubble sync)
    func speak(_ lines: [DialogLine], theme: DialogTheme, baseIndex: Int = 0) {
        guard !lines.isEmpty else { return }
        DebugLog.log("[TTS] speak() called — \(lines.count) lines, theme: \(theme.id), baseIndex: \(baseIndex), isPlayingBatch: \(isPlayingBatch)")

        // Interrupt filler if playing
        if isPlayingFiller {
            stop()
            isPlayingFiller = false
        }

        if isPlayingBatch {
            // Currently speaking — queue this batch for after the current one finishes
            dialogQueue.append((lines: lines, theme: theme, baseIndex: baseIndex))
            DebugLog.log("[TTS] Queued \(lines.count) lines (queue depth: \(dialogQueue.count))")
            return
        }

        startBatch(lines: lines, theme: theme, baseIndex: baseIndex)
    }

    /// Stop any in-progress playback and clear the queue
    func stop() {
        dialogQueue.removeAll()
        playbackTask?.cancel()
        playbackTask = nil
        isPlayingBatch = false
        currentLineIndex = -1
        stopPlayback()
    }

    // MARK: - Batch Playback

    private func startBatch(lines: [DialogLine], theme: DialogTheme, baseIndex: Int = 0) {
        playbackTask?.cancel()
        stopPlayback()

        isPlayingBatch = true
        DebugLog.log("[TTS] startBatch — \(lines.count) lines, baseIndex: \(baseIndex), sidecarReady: \(sidecarReady)")

        playbackTask = Task { @MainActor in
            defer {
                isPlayingBatch = false
                currentLineIndex = -1
                // Check for queued dialog — play next batch if available
                drainQueue()
            }

            // Ensure sidecar is up before trying to synthesize
            if !sidecarReady {
                DebugLog.log("[TTS] Waiting for sidecar...")
                await waitForSidecar(timeout: 10)
                DebugLog.log("[TTS] Sidecar wait done — ready: \(sidecarReady)")
                guard sidecarReady else {
                    DebugLog.log("[TTS] Sidecar not ready after wait, skipping batch")
                    return
                }
            }

            // Map dialog lines to TTS turns with correct voice IDs
            let turns: [(text: String, voiceID: String)] = lines.map { line in
                let voiceID = line.character == theme.char1 ? theme.voice1 : theme.voice2
                return (text: line.line, voiceID: voiceID)
            }

            DebugLog.log("[TTS] Synthesizing \(turns.count) turns: \(turns.map { "\($0.voiceID): \($0.text.prefix(30))" })")

            // Batch synthesize via sidecar
            let audioChunks = await synthesizeDialogue(turns: turns)

            guard !Task.isCancelled else {
                DebugLog.log("[TTS] Batch cancelled after synthesis")
                return
            }

            let validChunks = audioChunks.compactMap { $0 }.count
            DebugLog.log("[TTS] Got \(validChunks)/\(audioChunks.count) audio chunks, playing...")

            // Play each chunk sequentially — publish currentLineIndex so bubbles sync
            isSpeaking = true
            for (i, chunk) in audioChunks.enumerated() {
                guard !Task.isCancelled else { break }
                currentLineIndex = baseIndex + i
                guard let data = chunk else {
                    DebugLog.log("[TTS] Chunk \(i) was nil, skipping")
                    continue
                }
                await playAndWait(data: data)
            }
            isSpeaking = false
            DebugLog.log("[TTS] Batch playback finished")
        }
    }

    /// Drain the queue — if there's a queued batch, inject a cold open then play it.
    private func drainQueue() {
        guard !dialogQueue.isEmpty else { return }

        let next = dialogQueue.removeFirst()

        // Inject a cold open to bridge the gap between batches (10-15s of character banter)
        let coldOpen = pickColdOpen(theme: next.theme)
        var linesWithBridge = [DialogLine]()
        // Cold open doesn't map to a sessionDialog index, so offset baseIndex accordingly
        let coldOpenOffset = coldOpen != nil ? 1 : 0
        if let cold = coldOpen {
            linesWithBridge.append(cold)
        }
        linesWithBridge.append(contentsOf: next.lines)

        DebugLog.log("[TTS] Draining queue — playing next batch (\(linesWithBridge.count) lines, \(dialogQueue.count) remaining)")
        // baseIndex for cold open is -1 (won't match any sessionDialog line), real lines start after
        startBatch(lines: linesWithBridge, theme: next.theme, baseIndex: next.baseIndex - coldOpenOffset)
    }

    /// Pick a random cold open line from the theme's template, avoiding repeats.
    private func pickColdOpen(theme: DialogTheme) -> DialogLine? {
        guard !theme.coldOpens.isEmpty else { return nil }
        var idx: Int
        repeat {
            idx = Int.random(in: 0..<theme.coldOpens.count)
        } while idx == lastColdOpenIndex && theme.coldOpens.count > 1
        lastColdOpenIndex = idx

        // Alternate which character delivers the cold open
        let char = idx % 2 == 0 ? theme.char1 : theme.char2
        return DialogLine(character: char, line: theme.coldOpens[idx])
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

            // Strategy 1: Check if `autoclaw-theater` CLI is installed (pip install autoclaw-theater)
            let pipCLIPaths = [
                NSHomeDirectory() + "/.local/bin/autoclaw-theater",
                "/usr/local/bin/autoclaw-theater",
                "/opt/homebrew/bin/autoclaw-theater",
            ]

            var pipCLI: String?
            for path in pipCLIPaths {
                if FileManager.default.fileExists(atPath: path) {
                    pipCLI = path
                    break
                }
            }

            // Also check if it's on PATH via `which`
            if pipCLI == nil {
                let which = Process()
                which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                which.arguments = ["which", "autoclaw-theater"]
                let whichPipe = Pipe()
                which.standardOutput = whichPipe
                which.standardError = Pipe()
                try? which.run()
                which.waitUntilExit()
                if which.terminationStatus == 0,
                   let out = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !out.isEmpty {
                    pipCLI = out
                }
            }

            let pythonPath: String
            let args: [String]
            var workDir: String = NSHomeDirectory()

            if let cli = pipCLI {
                // pip-installed: use the entry point directly
                pythonPath = cli
                args = ["--port", "\(Self.port)", "--engine", "pocket"]
                DebugLog.log("[TTS] Found pip-installed sidecar: \(cli)")
            } else {
                // Strategy 2: Fall back to server.py in known directories
                let searchPaths = [
                    Bundle.main.bundlePath + "/../TTSSidecar",
                    NSHomeDirectory() + "/Documents/Claude Code/autoclaw-theater/autoclaw_theater",
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
                    DebugLog.log("[TTS] Sidecar not found — install via: pip install autoclaw-theater")
                    DebugLog.log("[TTS] Also searched directories: \(searchPaths)")
                    launchTask = nil
                    return
                }

                workDir = dir
                let serverScript = dir + "/server.py"
                let venvPython = dir + "/.venv/bin/python3"

                // Prefer venv Python (has all deps installed), fall back to system
                if FileManager.default.fileExists(atPath: venvPython) {
                    pythonPath = venvPython
                    args = [serverScript, "--port", "\(Self.port)", "--engine", "pocket"]
                } else {
                    pythonPath = "/usr/bin/env"
                    args = ["python3", serverScript, "--port", "\(Self.port)", "--engine", "pocket"]
                }
            }

            DebugLog.log("[TTS] Starting sidecar: \(pythonPath) \(args.joined(separator: " "))")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)

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
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioList = json["audio"] as? [String?]
            else {
                let body = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
                DebugLog.log("[TTS] Sidecar error — status: \(statusCode), body: \(body)")
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

// MARK: - Filler & Cold Open Content + Voice Cache

extension DialogVoiceService {

    private var cacheDirName: String { "voice-cache" }

    // MARK: - Loading

    /// Load fillers + cold opens from .autoclaw/ and prepare voice cache
    func loadContent(from projectPath: String, theme: DialogTheme) {
        let autoclawDir = "\(projectPath)/.autoclaw"
        let fm = FileManager.default

        // Ensure cache dir exists
        let cacheDir = "\(autoclawDir)/\(cacheDirName)"
        if !fm.fileExists(atPath: cacheDir) {
            try? fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        }

        // Load fillers
        loadDialogFile("\(autoclawDir)/fillers.json")
        // Load cold opens into same structure with "cold-" prefix
        loadDialogFile("\(autoclawDir)/cold-opens.json", keyPrefix: "cold-")

        DebugLog.log("[TTS] Loaded content — fillers: \(loadedFillers.filter { !$0.key.hasPrefix("cold-") }.count) themes, cold opens: \(loadedFillers.filter { $0.key.hasPrefix("cold-") }.count) themes")

        // Warm cache in background
        Task { @MainActor in
            await warmCache(theme: theme, cacheDir: cacheDir)
        }
    }

    private func loadDialogFile(_ path: String, keyPrefix: String = "") {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (themeId, value) in json {
            guard let conversations = value as? [[[String: String]]] else { continue }
            loadedFillers["\(keyPrefix)\(themeId)"] = conversations.map { conv in
                conv.compactMap { dict in
                    guard let char = dict["char"], let line = dict["line"] else { return nil }
                    return DialogLine(character: char, line: line)
                }
            }
        }
    }

    // MARK: - Voice Cache

    /// Cache key for a dialog line — hash of text + voiceID
    private func cacheKey(text: String, voiceID: String) -> String {
        let raw = "\(voiceID):\(text)"
        var hash: UInt64 = 5381
        for byte in raw.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return String(hash, radix: 16)
    }

    /// Get cached WAV data for a line, or nil if not cached
    func cachedAudio(text: String, voiceID: String, cacheDir: String) -> Data? {
        let key = cacheKey(text: text, voiceID: voiceID)
        let path = "\(cacheDir)/\(key).wav"
        return FileManager.default.contents(atPath: path)
    }

    /// Save WAV data to cache
    private func saveToCache(data: Data, text: String, voiceID: String, cacheDir: String) {
        let key = cacheKey(text: text, voiceID: voiceID)
        let path = "\(cacheDir)/\(key).wav"
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// Pre-synthesize all fillers + cold opens for the given theme
    private func warmCache(theme: DialogTheme, cacheDir: String) async {
        let ready = sidecarReady ? true : await checkSidecar()
        guard ready else {
            DebugLog.log("[TTS] Cache warm skipped — sidecar not ready")
            return
        }

        var toSynthesize: [(text: String, voiceID: String)] = []

        // Collect all lines that aren't cached yet
        for prefix in ["", "cold-"] {
            let key = "\(prefix)\(theme.id)"
            guard let convos = loadedFillers[key] else { continue }
            for convo in convos {
                for line in convo {
                    let voiceID = line.character == theme.char1 ? theme.voice1 : theme.voice2
                    if cachedAudio(text: line.line, voiceID: voiceID, cacheDir: cacheDir) == nil {
                        toSynthesize.append((text: line.line, voiceID: voiceID))
                    }
                }
            }
        }

        guard !toSynthesize.isEmpty else {
            DebugLog.log("[TTS] Cache already warm (\(cacheDir))")
            return
        }

        DebugLog.log("[TTS] Warming cache — \(toSynthesize.count) lines to synthesize")

        // Synthesize in batches of 6
        for batch in stride(from: 0, to: toSynthesize.count, by: 6) {
            let end = min(batch + 6, toSynthesize.count)
            let slice = Array(toSynthesize[batch..<end])
            let audioChunks = await synthesizeDialogue(turns: slice)
            for (i, chunk) in audioChunks.enumerated() {
                if let data = chunk {
                    saveToCache(data: data, text: slice[i].text, voiceID: slice[i].voiceID, cacheDir: cacheDir)
                }
            }
        }

        DebugLog.log("[TTS] Cache warm complete — \(toSynthesize.count) lines cached")
    }

    // MARK: - Cold Open

    /// Play a cold open immediately from cache. Returns true if played.
    /// The played cold open is permanently removed so it never repeats.
    func playColdOpen(theme: DialogTheme, projectPath: String) -> Bool {
        let cacheDir = "\(projectPath)/.autoclaw/\(cacheDirName)"
        let key = "cold-\(theme.id)"
        guard var coldOpens = loadedFillers[key], !coldOpens.isEmpty else { return false }

        // Pick a random cold open and remove it
        let idx = Int.random(in: 0..<coldOpens.count)
        let convo = coldOpens[idx]
        guard !convo.isEmpty else { return false }

        coldOpens.remove(at: idx)
        loadedFillers[key] = coldOpens

        // Persist removal to cold-opens.json
        removeConvoFromJSON(file: "\(projectPath)/.autoclaw/cold-opens.json", themeId: theme.id, index: idx)

        // Check if ALL lines are cached
        let allCached = convo.allSatisfy { line in
            let voiceID = line.character == theme.char1 ? theme.voice1 : theme.voice2
            return cachedAudio(text: line.line, voiceID: voiceID, cacheDir: cacheDir) != nil
        }

        if allCached {
            DebugLog.log("[TTS] Playing cold open from cache (\(convo.count) lines)")
            isPlayingFiller = true
            playCachedConvo(convo, theme: theme, cacheDir: cacheDir)
            return true
        }

        // Not cached yet — fall back to live TTS
        DebugLog.log("[TTS] Cold open not cached, using live TTS")
        isPlayingFiller = true
        startBatch(lines: convo, theme: theme, baseIndex: -100)
        return true
    }

    /// Play a conversation entirely from cache
    private func playCachedConvo(_ lines: [DialogLine], theme: DialogTheme, cacheDir: String) {
        playbackTask?.cancel()
        stopPlayback()
        isPlayingBatch = true

        playbackTask = Task { @MainActor in
            defer {
                isPlayingBatch = false
                isPlayingFiller = false
                currentLineIndex = -1
                drainQueue()
            }

            isSpeaking = true
            for (i, line) in lines.enumerated() {
                guard !Task.isCancelled else { break }
                currentLineIndex = -100 + i  // filler index range
                let voiceID = line.character == theme.char1 ? theme.voice1 : theme.voice2
                if let data = cachedAudio(text: line.line, voiceID: voiceID, cacheDir: cacheDir) {
                    await playAndWait(data: data)
                }
            }
            isSpeaking = false
        }
    }

    // MARK: - Filler Loop

    /// Start playing random filler dialog on a timer when idle
    func startFillerLoop(theme: DialogTheme, projectPath: String? = nil) {
        stopFillerLoop()
        let projPath = projectPath
        fillerTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playRandomFiller(theme: theme, projectPath: projPath)
            }
        }
    }

    func stopFillerLoop() {
        fillerTimer?.invalidate()
        fillerTimer = nil
    }

    private func playRandomFiller(theme: DialogTheme, projectPath: String?) {
        guard !isPlayingBatch, dialogQueue.isEmpty else { return }

        guard var fillers = loadedFillers[theme.id], !fillers.isEmpty else { return }

        // Pick a random filler and remove it so it never repeats
        let idx = Int.random(in: 0..<fillers.count)
        let filler = fillers[idx]
        guard !filler.isEmpty else { return }

        fillers.remove(at: idx)
        loadedFillers[theme.id] = fillers

        // Persist removal to fillers.json
        if let projPath = projectPath {
            removeConvoFromJSON(file: "\(projPath)/.autoclaw/fillers.json", themeId: theme.id, index: idx)
        }

        isPlayingFiller = true
        DebugLog.log("[TTS] Playing filler (\(filler.count) lines) for \(theme.id), \(fillers.count) remaining")

        // Try cache first
        if let projPath = projectPath {
            let cacheDir = "\(projPath)/.autoclaw/\(cacheDirName)"
            let allCached = filler.allSatisfy { line in
                let voiceID = line.character == theme.char1 ? theme.voice1 : theme.voice2
                return cachedAudio(text: line.line, voiceID: voiceID, cacheDir: cacheDir) != nil
            }
            if allCached {
                playCachedConvo(filler, theme: theme, cacheDir: cacheDir)
                return
            }
        }

        startBatch(lines: filler, theme: theme, baseIndex: -100)
    }

    /// Called when a real dialog batch arrives — stop filler, reset flag
    func interruptFiller() {
        if isPlayingFiller {
            isPlayingFiller = false
        }
    }

    // MARK: - Persist Removals

    /// Remove a conversation at `index` from a JSON file so it's never played again.
    private func removeConvoFromJSON(file: String, themeId: String, index: Int) {
        guard let data = FileManager.default.contents(atPath: file),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var convos = json[themeId] as? [[[String: String]]] else { return }

        guard index < convos.count else { return }
        convos.remove(at: index)
        json[themeId] = convos

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updated.write(to: URL(fileURLWithPath: file))
            DebugLog.log("[TTS] Removed played convo from \(file) (\(themeId)[\(index)]), \(convos.count) remaining")
        }
    }
}
