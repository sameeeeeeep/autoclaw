import Foundation
import Combine
import AppKit
import AutoclawTheater

// MARK: - Transcribe Service

/// Orchestrates the voice-to-cursor pipeline:
/// Record → background chunk transcription → on stop, combine raw chunks → inject at cursor → enhance in background.
///
/// Background loop every ~25s: transcribe audio chunk → store raw text.
/// On stop: drain remaining chunks → combine all raw text → inject immediately → enhance (non-blocking).
/// User sees "Listening..." while recording, then raw text appears instantly, enhanced version offered after.
@MainActor
final class TranscribeService: ObservableObject, TheaterDataSource {
    @Published var status: TranscribeStatus = .idle
    @Published var rawText = ""
    @Published var cleanText = ""
    @Published var enhancedText = ""
    @Published var isEnhancing = false
    /// Pre-prompt suggestion generated from project + session context before user speaks
    @Published var suggestedPrompts: [String] = []  // Two suggestions
    @Published var sessionDialog: [DialogLine] = []  // ELI5 character exchange
    @Published var isGeneratingPrompt = false
    var dialogTheme: DialogTheme = .default

    /// Legacy single suggestion accessor (first of two)
    var suggestedPrompt: String { suggestedPrompts.first ?? "" }

    private let voiceService: VoiceService
    private let ollamaService: OllamaService
    let dialogVoice = DialogVoiceService()

    /// The app user was in when they started transcribing
    var activeApp: String = ""
    /// Project context (CLAUDE.md summary) — set by AppState before start
    var projectContext: String = ""
    /// Session context (recent thread messages) — set by AppState before start
    var sessionContext: String = ""
    /// File paths for agentic context — Haiku reads these directly instead of pre-loaded text
    var projectPath: String?       // e.g. /Users/.../Autoclaw
    var sessionJSONLPath: String?  // e.g. /Users/.../.claude/projects/.../abc.jsonl

    /// Raw transcribed chunks accumulated during background processing
    private var rawChunks: [String] = []
    /// Background processing task
    private var backgroundTask: Task<Void, Never>?
    /// Pre-prompt generation task
    private var promptTask: Task<Void, Never>?

    /// Persistent Haiku session ID — context loaded once, reused for all pre-prompts
    private var haikuSessionId: String?
    /// Whether the Haiku session has been primed with project+session context
    private var haikuSessionPrimed = false
    /// File watcher for JSONL session changes (replaces polling)
    private var jsonlWatchSource: DispatchSourceFileSystemObject?
    private var jsonlFileDescriptor: Int32 = -1
    /// Debounce task — waits for writes to settle before firing Haiku
    private var debounceTask: Task<Void, Never>?

    // MARK: - Session Tempo Tracking
    /// Timestamps of recent JSONL write events — used to estimate session cadence
    private var recentWriteTimes: [Date] = []
    /// Timestamp of the last completed Haiku refresh
    private var lastRefreshTime: Date?
    /// In-flight refresh task — NOT cancelled by debounce resets
    private var refreshTask: Task<Void, Never>?
    /// Callback to get latest session context (set by AppState)
    var sessionContextProvider: (() -> String)?
    /// Last session context hash — only refresh when it changes
    private var lastSessionContextHash: Int = 0
    /// Running list of completed items this session — carried forward into refresh prompts
    private var completedItems: [String] = []

    /// How often to transcribe a chunk (seconds)
    private let chunkInterval: Float = 25.0

    /// Extract the sections of CLAUDE.md that help predict next actions.
    /// Prioritizes: gaps/next > build priority > current focus (truncated).
    static func extractActionableContext(_ fullContext: String) -> String {
        let lines = fullContext.components(separatedBy: "\n")

        // Extract named sections
        var sectionMap: [String: [String]] = [:]
        var currentKey = ""
        let wantedKeys = ["focus", "not built", "gaps", "priority", "next"]

        for line in lines {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.hasPrefix("#") {
                let matched = wantedKeys.first(where: { lower.contains($0) })
                currentKey = matched ?? ""
            } else if !currentKey.isEmpty {
                sectionMap[currentKey, default: []].append(line)
            }
        }

        // Build output: gaps/priority first (most actionable), then abbreviated focus
        var parts: [String] = []

        // 1. What's NOT built / remaining gaps — most important for prediction
        for key in ["not built", "gaps"] {
            if let lines = sectionMap[key], !lines.isEmpty {
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append("GAPS:\n\(String(text.prefix(500)))") }
            }
        }

        // 2. Build priority / next
        for key in ["priority", "next"] {
            if let lines = sectionMap[key], !lines.isEmpty {
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append("NEXT:\n\(String(text.prefix(300)))") }
            }
        }

        // 3. Current focus — abbreviated (just the first line of each bullet)
        if let focusLines = sectionMap["focus"], !focusLines.isEmpty {
            let bullets = focusLines
                .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- **") }
                .map { line -> String in
                    // Extract just "- **Name**: first sentence"
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let colonRange = trimmed.range(of: "**:") ?? trimmed.range(of: "**: ") {
                        let afterColon = trimmed[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                        let firstSentence = afterColon.components(separatedBy: ". ").first ?? String(afterColon.prefix(80))
                        let name = trimmed[trimmed.startIndex..<colonRange.lowerBound]
                        return "\(name)**: \(firstSentence)"
                    }
                    return String(trimmed.prefix(100))
                }
            if !bullets.isEmpty {
                parts.append("ACTIVE:\n\(bullets.joined(separator: "\n"))")
            }
        }

        let result = parts.joined(separator: "\n\n")
        return result.isEmpty ? String(fullContext.prefix(1000)) : String(result.prefix(1500))
    }

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
        promptTask?.cancel()
        promptTask = nil
        rawChunks = []
        rawText = ""
        cleanText = ""
        enhancedText = ""
        suggestedPrompts = []
        sessionDialog = []
        completedItems = []
        recentWriteTimes = []
        lastRefreshTime = nil
        isEnhancing = false
        isGeneratingPrompt = false
        status = .idle
        // Reset Haiku session so next Fn press primes fresh (stale session IDs return empty)
        resetHaikuSession()
        stopAutoRefresh()
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
        rawChunks = []
        status = .listening

        DebugLog.log("[Transcribe] Starting recording (backend: \(voiceService.activeBackend.rawValue), whisperKit loaded: \(voiceService.whisperKitService.isModelLoaded))")
        voiceService.startListening()

        // Start background chunk processing (transcribe + clean every ~25s)
        startBackgroundProcessing()
    }

    /// Stop recording → drain all chunks → combine raw text → inject immediately → enhance in background
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
            let whisperKit = voiceService.whisperKitService

            // 1. Pre-stop drain: grab any chunks WhisperKit completed but we haven't pulled yet
            let preStopChunks = whisperKit.takeCompletedChunks()
            if !preStopChunks.isEmpty {
                DebugLog.log("[Transcribe] Pre-stop drain: \(preStopChunks.count) unclaimed chunk(s)")
                for chunk in preStopChunks {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { rawChunks.append(trimmed) }
                }
            }

            // 2. Stop recording and transcribe remaining audio
            DebugLog.log("[Transcribe] Calling stopAndTranscribe...")
            let remainingRaw = await voiceService.stopAndTranscribe()
            let remainingTrimmed = remainingRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.log("[Transcribe] Remaining from WhisperKit (\(remainingTrimmed.count) chars): \(remainingTrimmed.prefix(200))")

            // 3. Post-stop drain: catch any chunk WhisperKit's bg loop finished during stop
            //    (edge case: WhisperKit was mid-transcription when we did pre-stop drain)
            let postStopChunks = whisperKit.takeCompletedChunks()
            if !postStopChunks.isEmpty {
                DebugLog.log("[Transcribe] Post-stop drain: \(postStopChunks.count) late chunk(s)")
                for chunk in postStopChunks {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { rawChunks.append(trimmed) }
                }
            }

            // 4. Add remaining audio
            if !remainingTrimmed.isEmpty {
                rawChunks.append(remainingTrimmed)
            }

            // 5. Combine all raw chunks → inject immediately (no cleanup delay)
            let fullRaw = rawChunks
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DebugLog.log("[Transcribe] Combined \(rawChunks.count) chunks (\(fullRaw.count) chars): \(fullRaw.prefix(200))")

            guard !fullRaw.isEmpty else {
                DebugLog.log("[Transcribe] Empty result — nothing to inject")
                status = .idle
                return
            }

            rawText = fullRaw
            cleanText = fullRaw

            // 6. Inject raw text at cursor IMMEDIATELY — no cleanup wait
            await injectText(fullRaw)

            // 7. Smart enhance in background (replaces old cleanup + enhance two-step)
            let app = activeApp
            Task { @MainActor in
                await enhanceWithModel(text: fullRaw, app: app)
            }

            // 8. Feed transcribed text back to Haiku session → get fresh predictions
            feedHaikuAndRefresh(userSaid: fullRaw)
        }
    }

    /// Feed what the user just said back to the persistent Haiku session and get updated predictions
    private func feedHaikuAndRefresh(userSaid text: String) {
        guard haikuSessionPrimed, let sessionId = haikuSessionId else { return }

        promptTask?.cancel()
        isGeneratingPrompt = true

        promptTask = Task { @MainActor in
            defer { isGeneratingPrompt = false }

            let followUp = "User just dictated: \"\(String(text.prefix(500)))\"\nReply with ONLY the JSON object (predictions + dialog), nothing else."

            do {
                let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)
                parsePrePromptResult(result)
            } catch {
                DebugLog.log("[PrePrompt] Feed-back failed: \(error)")
            }
        }
    }

    // MARK: - Background Chunk Processing

    /// Runs in background: every ~25s, pulls completed transcription chunks from WhisperKit.
    /// No cleanup — just accumulates raw text. Cleanup is skipped for speed; enhance handles quality.
    private func startBackgroundProcessing() {
        backgroundTask = Task { @MainActor in
            while !Task.isCancelled {
                // Wait for chunk interval
                try? await Task.sleep(nanoseconds: UInt64(chunkInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Pull any completed chunks from WhisperKit
                let whisperKit = voiceService.whisperKitService
                let chunks = whisperKit.takeCompletedChunks()

                for chunk in chunks {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    rawChunks.append(trimmed)
                    print("[Transcribe] Background chunk \(rawChunks.count): \(trimmed.prefix(80))...")
                }
            }
        }
    }

    // MARK: - JSONL File Watcher (event-driven refresh)

    /// Start watching a JSONL session file for changes — refreshes predictions when Claude Code writes new turns.
    /// Uses DispatchSource file watcher + 4s debounce (Claude streams multiple writes per response).
    func startAutoRefresh(watchingFile jsonlPath: String? = nil) {
        stopAutoRefresh()

        guard let path = jsonlPath, !path.isEmpty else {
            DebugLog.log("[PrePrompt] No JSONL path to watch, skipping file watcher")
            return
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            DebugLog.log("[PrePrompt] Could not open JSONL for watching: \(path)")
            return
        }
        jsonlFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.debouncedRefresh()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.jsonlFileDescriptor >= 0 {
                close(self.jsonlFileDescriptor)
                self.jsonlFileDescriptor = -1
            }
        }

        source.resume()
        jsonlWatchSource = source
        DebugLog.log("[PrePrompt] Watching JSONL for changes: \(path)")
    }

    // MARK: - Session Tempo

    /// Estimate how much time we have before the next JSONL change, based on recent write cadence.
    /// Returns a tempo classification that drives dialog length.
    enum SessionTempo: String {
        case rapid      // Writes every few seconds — Claude mid-response or fast back-and-forth. 2 lines.
        case active     // Writes every 10-30s — normal conversation pace. 3-4 lines.
        case relaxed    // Writes every 30-60s — user reading/thinking, Claude doing big work. 5-6 lines.
        case idle       // No writes for 60s+ — gap between sessions, user away. 3 lines (keep it light).

        var dialogTurns: Int {
            switch self {
            case .rapid:   return 2
            case .active:  return 4
            case .relaxed: return 6
            case .idle:    return 3
            }
        }

        var label: String {
            switch self {
            case .rapid:   return "rapid (2 turns)"
            case .active:  return "active (4 turns)"
            case .relaxed: return "relaxed (6 turns)"
            case .idle:    return "idle (3 turns)"
            }
        }
    }

    private func estimateTempo() -> SessionTempo {
        let now = Date()

        // Prune old entries (keep last 60s)
        recentWriteTimes = recentWriteTimes.filter { now.timeIntervalSince($0) < 60 }

        guard recentWriteTimes.count >= 2 else {
            // Not enough data — check time since last refresh
            if let last = lastRefreshTime, now.timeIntervalSince(last) > 60 {
                return .idle
            }
            return .active  // default
        }

        // Average interval between writes in the last 60s
        var intervals: [TimeInterval] = []
        for i in 1..<recentWriteTimes.count {
            intervals.append(recentWriteTimes[i].timeIntervalSince(recentWriteTimes[i - 1]))
        }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)

        // Time since the most recent write — are writes still coming?
        let sinceLastWrite = now.timeIntervalSince(recentWriteTimes.last!)

        if avgInterval < 5 && sinceLastWrite < 10 {
            return .rapid
        } else if avgInterval < 15 || sinceLastWrite < 30 {
            return .active
        } else if sinceLastWrite < 60 {
            return .relaxed
        } else {
            return .idle
        }
    }

    /// Debounce JSONL write events — adaptive delay based on session tempo.
    /// Claude Code streams responses, so a single assistant turn produces many rapid writes.
    /// Only resets the debounce timer — does NOT cancel any in-flight Haiku call.
    @MainActor
    private func debouncedRefresh() {
        // Record write timestamp for tempo tracking
        recentWriteTimes.append(Date())

        // Only reset the debounce timer, never cancel a running refresh
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5s debounce
            guard !Task.isCancelled else { return }

            // Don't stack refreshes — if one is already in flight, skip
            guard refreshTask == nil else {
                DebugLog.log("[PrePrompt] Refresh already in flight, skipping")
                return
            }

            refreshTask = Task { @MainActor in
                await self.refreshFromSessionChange()
                self.refreshTask = nil
            }
        }
    }

    /// Called after debounce settles — check if session context actually changed, then tell Haiku.
    @MainActor
    private func refreshFromSessionChange() async {
        guard haikuSessionPrimed, let sessionId = haikuSessionId else {
            DebugLog.log("[PrePrompt] Refresh skipped — primed: \(haikuSessionPrimed), sessionId: \(haikuSessionId ?? "nil")")
            return
        }
        guard let provider = sessionContextProvider else {
            DebugLog.log("[PrePrompt] Refresh skipped — no sessionContextProvider")
            return
        }

        let freshContext = provider()
        let freshHash = freshContext.hashValue
        guard !freshContext.isEmpty else {
            DebugLog.log("[PrePrompt] Refresh skipped — empty context")
            return
        }
        // Allow refresh if context changed OR enough time has passed (covers streaming where parsed content looks the same)
        let timeSinceRefresh = lastRefreshTime.map { Date().timeIntervalSince($0) } ?? 999
        if freshHash == lastSessionContextHash && timeSinceRefresh < 30 {
            DebugLog.log("[PrePrompt] Refresh skipped — context unchanged, only \(Int(timeSinceRefresh))s since last refresh")
            return
        }
        lastSessionContextHash = freshHash

        let tempo = estimateTempo()
        DebugLog.log("[PrePrompt] JSONL changed, refreshing predictions... tempo: \(tempo.label)")
        isGeneratingPrompt = true
        defer {
            isGeneratingPrompt = false
            lastRefreshTime = Date()
        }

        // Auto-extract completed items: if previous predictions are close to what just happened,
        // they're likely done — add them to the running completed list
        extractCompletedItems(from: freshContext)

        let dialogHint = AppSettings.shared.theaterMode
            ? " (predictions + dialog). Dialog: exactly \(tempo.dialogTurns) lines about the SPECIFIC thing in the latest messages below. Name the file/function/feature."
            : ""

        // Carry forward previous predictions so model can course-correct
        var prevPredictions = ""
        if !suggestedPrompts.isEmpty {
            prevPredictions = "Session update. Previous predictions were:\n"
            for (i, p) in suggestedPrompts.enumerated() {
                prevPredictions += "\(i + 1). \(p)\n"
            }
            prevPredictions += "\n"
        }

        // Running completed list for accumulated state
        var completedBlock = ""
        if !completedItems.isEmpty {
            completedBlock = "\nCompleted so far this session:\n"
            for item in completedItems.suffix(10) {
                completedBlock += "- \(item)\n"
            }
            completedBlock += "\n"
        }

        let courseCorrect = suggestedPrompts.isEmpty
            ? ""
            : "Were previous predictions close? If yes, predict the NEXT step after what just happened.\nIf no, re-read the activity and predict fresh.\n\n"

        let followUp = """
        \(prevPredictions)\(completedBlock)\
        Session update — re-read the last ~100 lines of the JSONL to see what changed.
        Update the board (move completed items to Done, add new Todo items you think should happen).
        \(courseCorrect)\
        Then reply with ONLY the JSON object\(dialogHint) — predictions for what's NEXT.
        """

        do {
            let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)
            parsePrePromptResult(result)
            DebugLog.log("[PrePrompt] Refresh completed successfully")
        } catch {
            DebugLog.log("[PrePrompt] Refresh failed: \(error)")
        }
    }

    /// Lightweight heuristic: scan session context for completion signals and add to running list.
    /// Looks for patterns like "Done.", "✅", "created", "updated", "fixed" near file names.
    private func extractCompletedItems(from context: String) {
        let lines = context.components(separatedBy: "\n")
        let completionPatterns = ["done", "✅", "successfully", "created ", "updated ", "fixed ", "refactored ", "replaced ", "removed ", "added "]
        for line in lines.suffix(30) {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            guard completionPatterns.contains(where: { lower.contains($0) }) else { continue }
            // Extract a short summary (first 100 chars, skip if too short to be useful)
            let summary = String(line.trimmingCharacters(in: .whitespaces).prefix(100))
            guard summary.count > 10, !completedItems.contains(summary) else { continue }
            completedItems.append(summary)
        }
        // Cap at 15 most recent to keep prompt size bounded
        if completedItems.count > 15 {
            completedItems = Array(completedItems.suffix(15))
        }
    }

    /// Stop watching the JSONL file
    func stopAutoRefresh() {
        debounceTask?.cancel()
        debounceTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        jsonlWatchSource?.cancel()
        jsonlWatchSource = nil
    }

    // MARK: - Pre-Prompt Generation

    /// Reset the persistent Haiku session (call when project/session changes)
    func resetHaikuSession() {
        haikuSessionId = nil
        haikuSessionPrimed = false
        completedItems = []
    }

    /// Generate contextual prompt suggestions based on project + session + active app.
    /// Uses a persistent Haiku session — context loaded once, predictions are lightweight follow-ups.
    /// Returns 2 suggestions so the user can pick the most relevant one.
    func generatePrePrompt() {
        // Sync theme from settings
        dialogTheme = DialogTheme.find(AppSettings.shared.dialogThemeId)

        // Need context to generate a suggestion — either file paths or inline text
        guard projectPath != nil || sessionJSONLPath != nil || !projectContext.isEmpty || !sessionContext.isEmpty else {
            DebugLog.log("[PrePrompt] SKIP — no context available")
            return
        }

        // Prevent triple-prime: if a prime is already in flight, skip
        if promptTask != nil {
            DebugLog.log("[PrePrompt] SKIP — already in flight (session: \(haikuSessionId ?? "new"))")
            return
        }

        suggestedPrompts = []
        isGeneratingPrompt = true
        DebugLog.log("[PrePrompt] STARTED — project: \(projectPath ?? "nil"), jsonl: \(sessionJSONLPath?.suffix(40) ?? "nil"), app: \(activeApp), haiku session: \(haikuSessionId ?? "new")")

        promptTask = Task { @MainActor in
            defer {
                isGeneratingPrompt = false
                promptTask = nil  // Allow future generatePrePrompt() calls
                DebugLog.log("[PrePrompt] DONE — \(suggestedPrompts.count) suggestions")
            }

            do {
                // Ensure .autoclaw/ briefing folder exists
                if let projPath = projectPath {
                    let autoclawDir = "\(projPath)/.autoclaw"
                    let contextFile = "\(autoclawDir)/context.md"
                    let fm = FileManager.default
                    if !fm.fileExists(atPath: autoclawDir) {
                        try? fm.createDirectory(atPath: autoclawDir, withIntermediateDirectories: true)
                    }
                    if !fm.fileExists(atPath: contextFile) {
                        // Seed from CLAUDE.md if available, otherwise create a starter
                        let claudeMD = "\(projPath)/CLAUDE.md"
                        let readme = "\(projPath)/README.md"
                        if let content = try? String(contentsOfFile: claudeMD, encoding: .utf8) {
                            let brief = Self.extractActionableContext(content)
                            try? brief.write(toFile: contextFile, atomically: true, encoding: .utf8)
                            DebugLog.log("[PrePrompt] Seeded .autoclaw/context.md from CLAUDE.md (\(brief.count) chars)")
                        } else if let content = try? String(contentsOfFile: readme, encoding: .utf8) {
                            let brief = String(content.prefix(2000))
                            try? brief.write(toFile: contextFile, atomically: true, encoding: .utf8)
                            DebugLog.log("[PrePrompt] Seeded .autoclaw/context.md from README.md")
                        } else {
                            let starter = "# Project Context\n\nAdd project goals, priorities, and product context here.\nThis file is read by Autoclaw's PM agent to make predictions."
                            try? starter.write(toFile: contextFile, atomically: true, encoding: .utf8)
                            DebugLog.log("[PrePrompt] Created starter .autoclaw/context.md")
                        }
                    }
                    // Seed board.md if missing
                    let boardFile = "\(autoclawDir)/board.md"
                    if !fm.fileExists(atPath: boardFile) {
                        let board = """
                        # Board

                        ## Todo

                        ## In Progress

                        ## Done
                        """
                        try? board.write(toFile: boardFile, atomically: true, encoding: .utf8)
                        DebugLog.log("[PrePrompt] Created .autoclaw/board.md")
                    }
                }

                // First call: prime the session with full context
                if !haikuSessionPrimed {
                    let sessionId = UUID().uuidString
                    haikuSessionId = sessionId

                    // Build the PM's briefing — file paths only, Haiku reads what it needs
                    let autoclawDir = projectPath.map { "\($0)/.autoclaw" }
                    let contextFile = autoclawDir.map { "\($0)/context.md" }

                    let boardFile = autoclawDir.map { "\($0)/board.md" }

                    var filesBlock = ""
                    if let ctx = contextFile {
                        filesBlock += "PROJECT BRIEF (read first — product context):\n\(ctx)\n\n"
                    }
                    if let jsonl = sessionJSONLPath {
                        filesBlock += "SESSION JSONL (live conversation — read last ~200 lines for current activity):\n\(jsonl)\n\n"
                    }
                    if let board = boardFile {
                        filesBlock += "BOARD (your kanban — read it, update it each round):\n\(board)\n\n"
                    }
                    if let dir = autoclawDir {
                        filesBlock += "DOCS FOLDER (any extra docs + where you write):\n\(dir)/\n"
                    }

                    let theaterOn = AppSettings.shared.theaterMode
                    let dialogInstructions: String
                    if theaterOn {
                        let initialTurns = estimateTempo().dialogTurns
                    dialogInstructions = """
                        2. Write a \(initialTurns)-line dialog between \(dialogTheme.char1) and \(dialogTheme.char2) (\(dialogTheme.show)) about what's happening in the session.
                           - FLOWING conversation: each line responds to the previous. ELI5 — explain technical terms via show-universe analogies.
                           - Reference the user as "\(dialogTheme.boss)".
                           - Dialog must be about the LATEST session activity. Name the specific file/function/feature.
                           - Exactly \(initialTurns) lines. Each under 120 chars.
                        """
                    } else {
                        dialogInstructions = "2. Skip dialog — omit the \"dialog\" field entirely."
                    }

                    let dialogFormat = theaterOn
                        ? "\"dialog\":[{\"char\":\"\(dialogTheme.char1)\",\"line\":\"...\"},{\"char\":\"\(dialogTheme.char2)\",\"line\":\"...\"},...]"
                        : ""
                    let formatExample = theaterOn
                        ? "{\"predictions\":[\"<p1>\",\"<p2>\"],\(dialogFormat)}"
                        : "{\"predictions\":[\"<p1>\",\"<p2>\"]}"

                    let personalityGuide = theaterOn ? "\n\(dialogTheme.personality)" : ""

                    let primePrompt = """
                    You are a product manager running in parallel to a developer's Claude Code session.
                    You watch the session, maintain a project board, and predict what gets built next.

                    === EVERY ROUND, YOU DO THREE THINGS ===

                    1. UPDATE THE BOARD — read board.md, then rewrite it:
                       - Move completed items (things done in the session) to ## Done
                       - Move the current focus to ## In Progress
                       - Add new tasks to ## Todo that you think should happen next (from product perspective)
                       - Keep items concise (one line each). Cap at 8 todo, 3 in-progress, 15 done.
                       - Write the updated board back to the board.md file.

                    2. RETURN TWO PREDICTIONS — the next things the user will tell Claude to build
                    \(dialogInstructions)
                    \(personalityGuide)

                    === YOUR ROLE ===

                    You're a PM, not a code reviewer. Think product: what ships next, what connects to what, what gaps remain.
                    Everything in the session is DONE. Predict what HASN'T happened yet.
                    You can also add tasks to the board that the user hasn't mentioned — things a good PM would flag.

                    Predictions:
                    - Start with a verb (add, wire, fix, implement, connect)
                    - Reference actual features/files from the session or project brief
                    - Under 100 chars, actionable by Claude

                    === YOUR FILES ===

                    You can ONLY access files in the .autoclaw/ folder and the session JSONL. No direct codebase access.
                    Read project brief first, then session JSONL, then board.

                    \(filesBlock)

                    You will be called repeatedly as the session progresses. Update the board each time.

                    === OUTPUT ===

                    FIRST: Update the board (write to board.md).
                    THEN: Reply with ONLY a JSON object. No markdown, no explanation.
                    Format: \(formatExample)
                    Predictions: exactly 2, under 100 chars each.
                    \(theaterOn ? "Dialog: reference the specific thing from the latest session activity. Stay in character. Each line under 120 chars." : "")
                    """

                    DebugLog.log("[PrePrompt] Priming Haiku session \(sessionId)...")
                    let result = try await callClaudeCLI(prompt: primePrompt, model: "haiku", sessionId: sessionId)
                    haikuSessionPrimed = true
                    // Seed the hash so auto-refresh doesn't immediately re-fire
                    if let provider = sessionContextProvider {
                        lastSessionContextHash = provider().hashValue
                    }
                    parsePrePromptResult(result)

                } else if let sessionId = haikuSessionId {
                    // Follow-up: just ask for next prediction (context already loaded)
                    let followUp = "Active app: \(activeApp).\nReply with ONLY the JSON object (predictions + dialog), nothing else."

                    DebugLog.log("[PrePrompt] Resuming Haiku session \(sessionId)...")
                    let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)

                    // If resume returned empty (stale session), reset and re-prime from scratch
                    if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DebugLog.log("[PrePrompt] Stale session — resetting and re-priming...")
                        resetHaikuSession()
                        generatePrePrompt()
                        return
                    }

                    parsePrePromptResult(result)
                }
            } catch {
                DebugLog.log("[PrePrompt] FAILED: \(error)")
            }
        }
    }

    /// Parse Haiku's response into predictions + dialog
    private func parsePrePromptResult(_ result: String) {
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        guard !Task.isCancelled else {
            DebugLog.log("[PrePrompt] CANCELLED")
            return
        }

        guard !cleaned.isEmpty && !cleaned.contains("\"type\":\"error\"") else {
            DebugLog.log("[PrePrompt] Bad result: \"\(cleaned.prefix(100))\"")
            return
        }

        func cleanText(_ raw: String) -> String {
            raw.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespaces)
        }

        func isUsable(_ s: String) -> Bool {
            !s.isEmpty && s.count > 5 && !s.hasSuffix(":") && !s.hasPrefix("GO")
        }

        var prompts: [String] = []
        var dialog: [DialogLine] = []

        // 1. Try JSON object parse: {"predictions":[...], "dialog":[...]}
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            let jsonStr = String(cleaned[start...end])
            if let data = jsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Extract predictions
                if let preds = obj["predictions"] as? [String] {
                    prompts = preds.map { cleanText($0) }.filter { isUsable($0) }
                    prompts = Array(prompts.prefix(2))
                }
                // Extract dialog (2-6 lines depending on session activity)
                if let dialogArr = obj["dialog"] as? [[String: String]] {
                    for d in dialogArr.prefix(6) {
                        if let char = d["char"], let line = d["line"], !line.isEmpty {
                            dialog.append(DialogLine(character: cleanText(char), line: cleanText(line)))
                        }
                    }
                }
            }
        }

        // 2. Fallback: try JSON array (old format) for predictions only
        if prompts.isEmpty, let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]") {
            let jsonStr = String(cleaned[start...end])
            if let data = jsonStr.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                prompts = arr.map { cleanText($0) }.filter { isUsable($0) }
                prompts = Array(prompts.prefix(2))
            }
        }

        // 3. Last resort: extract A:/B: lines or first usable lines
        if prompts.isEmpty {
            for line in cleaned.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let range = trimmed.range(of: #"^[AB]:\s*"#, options: .regularExpression) {
                    let prediction = cleanText(String(trimmed[range.upperBound...]))
                    if isUsable(prediction) { prompts.append(prediction) }
                }
                if prompts.count >= 2 { break }
            }
        }
        if prompts.isEmpty {
            let fallback = cleaned.components(separatedBy: "\n")
                .map { cleanText($0) }
                .filter { isUsable($0) }
            prompts = Array(fallback.prefix(2))
        }

        suggestedPrompts = prompts
        // Track where new lines will start in the sessionDialog array (for TTS bubble sync)
        let newLinesBaseIndex = sessionDialog.count
        // Append new dialog lines — don't replace, so current TTS playback isn't disrupted
        sessionDialog.append(contentsOf: dialog)
        DebugLog.log("[PrePrompt] Parsed \(suggestedPrompts.count) predictions, \(sessionDialog.count) dialog lines (appended \(dialog.count))")
        for (i, p) in prompts.enumerated() {
            DebugLog.log("[PrePrompt] Prediction \(i+1): \(p)")
        }
        for d in dialog {
            DebugLog.log("[PrePrompt] Dialog: \(d.character): \(d.line)")
        }

        // Speak dialog lines aloud via TTS sidecar if theater mode is on (non-blocking)
        if !dialog.isEmpty && AppSettings.shared.theaterMode {
            dialogVoice.speak(dialog, theme: dialogTheme, baseIndex: newLinesBaseIndex)
        }
    }

    // MARK: - Injection

    /// Inject a specific pre-prompt suggestion at cursor
    func injectPrePrompt(at index: Int = 0) {
        guard index < suggestedPrompts.count else { return }
        let text = suggestedPrompts[index]
        guard !text.isEmpty else { return }
        suggestedPrompts = []
        Task { @MainActor in
            await CursorInjector.type(text)
            print("[Transcribe] Injected pre-prompt: \(text.prefix(60))...")
        }
    }

    /// Inject arbitrary text at cursor (used by board widget)
    func injectText(_ text: String) {
        guard !text.isEmpty else { return }
        Task { @MainActor in
            await CursorInjector.type(text)
            print("[Transcribe] Injected board item: \(text.prefix(60))...")
        }
    }

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

        // Build context block from project + session (if available)
        var contextBlock = ""
        if !projectContext.isEmpty {
            contextBlock += "\nProject context:\n\(projectContext)\n"
        }
        if !sessionContext.isEmpty {
            contextBlock += "\nRecent session activity:\n\(sessionContext)\n"
        }

        let prompt: String
        if contextBlock.isEmpty {
            prompt = """
            Rewrite this dictated text. Keep the speaker's voice and intent. \
            Make it sharper and clearer. If it's already clean, return it mostly as-is. \
            Remove filler words and false starts. \
            Tone: \(appContext). Active app: \(app). \
            Return ONLY the improved text, nothing else.

            "\(text)"
            """
        } else {
            prompt = """
            Enhance this dictated text. You have project context below. \
            RULES: \
            - Fix grammar, remove filler, tighten phrasing \
            - If the speaker references something vague that clearly maps to a specific file/function/variable from context, substitute the specific name \
            - If the speaker's intent is ambiguous, preserve the ambiguity — do NOT guess \
            - NEVER add details the speaker didn't reference or imply \
            - NEVER change the speaker's intent or add instructions they didn't give \
            - Keep their voice — if they're casual, stay casual \
            Tone: \(appContext). Active app: \(app).
            \(contextBlock)
            Return ONLY the enhanced text, nothing else. Do NOT wrap your response in quotes.

            ---
            \(text)
            ---
            """
        }

        do {
            let result = try await callClaudeCLI(prompt: prompt, model: provider.modelFlag)
            var cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip surrounding quotes — LLM sometimes wraps its response in them
            if cleaned.count >= 2 && cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
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

    private func callClaudeCLI(prompt: String, model: String = "haiku", sessionId: String? = nil, resume: Bool = false) async throws -> String {
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
                var args = ["--model", model, "-p", prompt, "--output-format", "text", "--dangerously-skip-permissions", "--allowedTools", "Read,Glob,Write"]
                if let sid = sessionId {
                    if resume {
                        args += ["--resume", sid]
                    } else {
                        args += ["--session-id", sid]
                    }
                }
                process.arguments = args

                // Set CWD to a safe directory to prevent the CLI from scanning protected locations
                process.currentDirectoryURL = home.appendingPathComponent(".claude")

                let homePath = home.path
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = homePath
                // Prevent claude CLI from loading MCP servers that might access protected directories
                env["DISABLE_MCP_SERVERS"] = "1"
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
