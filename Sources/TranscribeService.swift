import Foundation
import Combine
import AppKit

// MARK: - Dialog Line (ELI5 character exchange)

struct DialogLine: Identifiable {
    let id = UUID()
    let character: String
    let line: String
}

// MARK: - Dialog Theme (character pair for ELI5 banter)

struct DialogTheme {
    let id: String
    let char1: String
    let char2: String
    let boss: String   // Third character — the user's avatar who gives them work
    let show: String
    let style: String  // Brief personality guide for Haiku
    let voice1: String // TTS sidecar voice ID for char1
    let voice2: String // TTS sidecar voice ID for char2

    /// Character-specific guardrails: signature phrases, catchphrases, show-universe analogies.
    /// Injected into the pre-prompt so Haiku writes dialog that *sounds* like the characters
    /// without needing a heavier model.
    let personality: String

    /// Cold open templates — short 1-2 line quips the characters would say while waiting
    /// for the next full dialog to generate. Rotated randomly. Keep under 80 chars each.
    let coldOpens: [String]

    static let all: [DialogTheme] = [
        .init(id: "gilfoyle-dinesh", char1: "Gilfoyle", char2: "Dinesh", boss: "Richard",
              show: "Silicon Valley",
              style: "Gilfoyle is deadpan/sardonic, Dinesh is defensive/animated. They roast each other while explaining code.",
              voice1: "gilfoyle", voice2: "dinesh",
              personality: """
              CHARACTER VOICE GUIDE:
              • Gilfoyle speaks in flat, deadpan statements. Never exclaims. Insults Dinesh as a reflex. References Satan, dark metal, and nihilism casually. Example: "Your code has the structural integrity of a wet napkin."
              • Dinesh gets defensive immediately, overexplains, and takes everything personally. Brags about things that aren't impressive. Example: "I once deployed a model that only crashed twice. In production."
              • When explaining tech: frame it like a Pied Piper engineering debate. APIs are "middle-out compression for HTTP". A database is "Dinesh's attempt at organizing anything". Git conflicts are "when two people try to use Dinesh's code at the same time — which never happens".
              • Reference: Dinesh's gold chain, Gilfoyle's server rack, Big Head failing upward, Jian-Yang's hot dog app.
              """,
              coldOpens: [
                "Dinesh, your last commit message was just an emoji.",
                "I'm not saying your code is bad, but my IDE flagged it as malware.",
                "Oh good, Richard's back. Hide the production server.",
                "I wrote a script that automatically reverts Dinesh's commits.",
              ]),
        .init(id: "david-moira", char1: "David", char2: "Moira", boss: "Johnny",
              show: "Schitt's Creek",
              style: "David is anxious/dramatic, Moira uses elaborate vocabulary and references her acting career. They overreact to mundane code changes.",
              voice1: "david-rose", voice2: "moira-rose",
              personality: """
              CHARACTER VOICE GUIDE:
              • David is horrified by anything messy or unstructured. Uses "Um" and "Okay" as full sentences. Gestures wildly. Treats code formatting like interior design — "This indentation is a CHOICE and not a good one." Example: "I just need everyone to know that I am NOT okay with this merge conflict."
              • Moira speaks in ornate, quasi-Shakespearean vocabulary. Drops dramatic pauses. References her acting career for everything. Pronounces things oddly. Example: "This deployment reminds me of my time in Sunrise Bay — chaotic, ill-rehearsed, and someone always dies in the third act."
              • When explaining tech: frame things as Rose family drama. A server crash is "the day we lost Rose Video all over again". Refactoring is "reorganizing one's closet of bespoke code garments". An API is "a concierge — you ask nicely, and sometimes it delivers".
              • Reference: David's store, Moira's wigs, Alexis's "Ew David!", Stevie's deadpan, the motel.
              """,
              coldOpens: [
                "Ew, David, this code is giving me anxiety.",
                "I once performed a twelve-hour deploy. Standing ovation. Well, eventually.",
                "This is simply NOT the aesthetic I was promised.",
                "Johnny's back and he brought... more requirements.",
              ]),
        .init(id: "dwight-jim", char1: "Dwight", char2: "Jim", boss: "Michael",
              show: "The Office",
              style: "Dwight is intense/literal ('FALSE.'), Jim is sarcastic and looks at the camera. Dwight relates everything to beet farming or survival skills.",
              voice1: "dwight", voice2: "jim",
              personality: """
              CHARACTER VOICE GUIDE:
              • Dwight is dead serious about everything. Says "FALSE." and "FACT:" as sentence starters. Relates all tech to beet farming, martial arts, or survival. Example: "A merge conflict is like two bears fighting over the same salmon. Only one survives. And that bear is ME."
              • Jim is bemused, sarcastic, speaks directly to the audience with deadpan asides. Uses "So..." to start observations. Example: "So apparently Dwight has been running a backup server under his desk. For three years."
              • When explaining tech: Dwight treats code like Schrute Farms operations. A deployment is "the harvest". Unit tests are "inspecting each beet by hand". A bug is "an infiltrator" he will "neutralize". Jim translates everything to normal.
              • Reference: Michael's "That's what she said", beet farming, the Dunder Mifflin parking lot, Dwight's desk weapons, Jim's pranks.
              """,
              coldOpens: [
                "FACT: I could have written this in assembly. By hand.",
                "So... Dwight just called a syntax error 'an act of war'.",
                "Michael just asked if we can make the code 'more fun'. So.",
                "Bears. Beets. Battlestar Galactica. And now, apparently, bash scripts.",
              ]),
        .init(id: "chandler-joey", char1: "Chandler", char2: "Joey", boss: "Ross",
              show: "Friends",
              style: "Chandler uses 'Could this BE any more...' sarcasm, Joey is lovably confused but asks the questions a non-programmer would ask.",
              voice1: "chandler", voice2: "joey",
              personality: """
              CHARACTER VOICE GUIDE:
              • Chandler deflects with sarcasm. Emphasizes random words. Uses "Could this BE any more..." and "Yes, that's what I said" patterns. Self-deprecating. Example: "Could this deployment BE any slower? Oh wait, that was my code."
              • Joey is genuinely confused but asks the RIGHT questions — the ones a beginner needs answered. Uses "How YOU doin'?" for everything, including greeting servers. Example: "So the API is like... a waiter? You tell it what you want and it brings you data? ...Does it take tips?"
              • When explaining tech: frame things like apartment life. A server is "the apartment" and tenants are "processes". Memory leaks are "Joey eating everyone's food — eventually there's nothing left". A firewall is "the door chain that keeps out Ugly Naked Guy".
              • Reference: Central Perk, "WE WERE ON A BREAK" (for rollbacks), Joey doesn't share food (memory), Chandler's job that no one understands.
              """,
              coldOpens: [
                "Could this build time BE any longer?",
                "So, like, is the cloud an ACTUAL cloud? Up in the sky?",
                "Ross is back and he wants to talk about 'proper architecture'. Again.",
                "I don't even understand what Chandler's code DOES and neither does he.",
              ]),
        .init(id: "rick-morty", char1: "Rick", char2: "Morty", boss: "Jerry",
              show: "Rick and Morty",
              style: "Rick is genius/dismissive with *burps*, Morty is anxious but grounds the explanation in simple terms.",
              voice1: "rick", voice2: "morty",
              personality: """
              CHARACTER VOICE GUIDE:
              • Rick stutters, burps mid-sentence (write as *burp*), dismisses everything as trivial. Genius-level but impatient. Uses "Morty" as punctuation. Example: "It's a — *burp* — recursive function, Morty. It calls itself. Like your mom calling me for tech support."
              • Morty is nervous, stutters ("Oh geez", "I-I don't know Rick"), but his confusion forces Rick to actually explain things simply. He's the audience surrogate. Example: "W-wait, so the database just... FORGETS things? That seems bad, Rick!"
              • When explaining tech: frame everything as interdimensional science. A microservice is "a tiny universe that only does one thing". Docker is "a portal gun for code — same app, any dimension". A race condition is "two Ricks from different timelines editing the same file".
              • Reference: portal gun, Pickle Rick, Szechuan sauce, the garage lab, "wubba lubba dub dub", Jerry being useless.
              """,
              coldOpens: [
                "Listen Morty, I could — *burp* — rewrite this whole thing in 20 minutes.",
                "Oh geez Rick, Jerry's back and he wants a 'simple feature'. Those are never simple.",
                "I turned myself into a deployment pipeline, Morty! I'm Pipeline Rick!",
                "W-what do you mean the tests are 'optional', Rick?!",
              ]),
        .init(id: "sherlock-watson", char1: "Sherlock", char2: "Watson", boss: "Lestrade",
              show: "Sherlock",
              style: "Sherlock makes rapid deductions, Watson translates to plain English. 'Elementary' moments.",
              voice1: "sherlock", voice2: "watson",
              personality: """
              CHARACTER VOICE GUIDE:
              • Sherlock rattles off deductions at machine-gun speed. Sees patterns others miss. Condescending but brilliant. Uses "Obviously" and "Elementary" and "Dull." Example: "The crash at line 47 — caused by a null pointer, introduced three commits ago, by someone who clearly doesn't understand optional chaining. Obviously."
              • Watson is impressed but exasperated. Translates Sherlock's deductions into normal language. Grounding. Military precision. Example: "Right, so what Sherlock MEANS is — the app crashed because of a missing check. We add one line and it's fixed."
              • When explaining tech: frame debugging as crime solving. A stack trace is "the crime scene". Logs are "witness statements". A bug is "the culprit". Git blame is "literally the investigation tool". The codebase is "the case".
              • Reference: 221B Baker Street, "The game is afoot!", Mrs. Hudson, Moriarty as the ultimate bug, Sherlock's mind palace for architecture diagrams.
              """,
              coldOpens: [
                "The stack trace tells me everything. You see but you do not observe.",
                "What Sherlock MEANS is the build failed. Again. For normal reasons.",
                "Lestrade's sent another ticket. He thinks it's 'urgent'. It never is.",
                "I've solved it. The bug was introduced at 3:47 AM by a sleep-deprived developer.",
              ]),
        .init(id: "jesse-walter", char1: "Jesse", char2: "Walter", boss: "Gus",
              show: "Breaking Bad",
              style: "Jesse says 'Yeah science!' and uses slang, Walter is methodical/precise. They treat code like a cook.",
              voice1: "jesse", voice2: "walter",
              personality: """
              CHARACTER VOICE GUIDE:
              • Jesse is enthusiastic but informal. Says "Yo", "Yeah science!", "bitch" (as emphasis, not insult). Streetwise explanations. Example: "Yo, so basically this function takes your data and cooks it into something useful. Yeah chemistry! Well, computer chemistry!"
              • Walter is precise, methodical, takes pride in purity. Treats code quality like cook purity — 99.1% isn't good enough. Lectures. Example: "This isn't just code, Jesse. This is CRAFT. 96% test coverage? Unacceptable. We are not amateurs."
              • When explaining tech: frame everything as a cook. Writing code is "cooking". Dependencies are "precursors". The build is "the batch". Code review is "quality control". Deployment is "distribution". A clean codebase is "99.1% pure".
              • Reference: "Say my name", the RV, Los Pollos Hermanos (Gus's clean front), "I am the one who knocks" (deploys), blue product = clean code.
              """,
              coldOpens: [
                "Yo Mr. White, the build is like... 99.1% passing. That's good right?",
                "Jesse. We do not ship code that is merely 'good enough'.",
                "Gus wants the next feature by Friday. I am the one who deploys.",
                "Yeah science! Wait, computer science counts, right?",
              ]),
        .init(id: "tony-jarvis", char1: "Tony", char2: "JARVIS", boss: "Pepper",
              show: "Iron Man",
              style: "Tony is quippy/confident, JARVIS is dry/precise with probability calculations.",
              voice1: "tony", voice2: "jarvis",
              personality: """
              CHARACTER VOICE GUIDE:
              • Tony is cocky, fast-talking, makes pop culture references. Treats coding like building suits — iterating on Mark I, II, III. Uses nicknames for everything. Example: "JARVIS, pull up the logs. And get me a coffee. Actually, make the coffee first."
              • JARVIS is dry, precise, British-polite. Gives probability assessments for everything. Subtle wit under the formality. Example: "Sir, there is a 73% probability that this refactor will introduce new bugs. Shall I prepare the rollback?"
              • When explaining tech: frame everything as Stark Industries R&D. A new feature is "a new suit". The test suite is "running diagnostics". A bug is "armor breach". CI/CD is "the assembly line". The cloud is "the Stark satellite network".
              • Reference: Arc reactor, "I am Iron Man", Pepper managing the chaos, the workshop, "Sir", probability percentages, Mark suit numbers.
              """,
              coldOpens: [
                "JARVIS, what's the damage report on that last merge?",
                "Sir, I calculate a 12% chance Pepper won't notice we broke staging.",
                "Let's call this build Mark XVII. Lucky number.",
                "Shall I prepare the rollback, sir? ...I'll prepare the rollback.",
              ]),
    ]

    static let `default` = all[0]

    static func find(_ id: String) -> DialogTheme {
        all.first { $0.id == id } ?? .default
    }
}

// MARK: - Transcribe Service

/// Orchestrates the voice-to-cursor pipeline:
/// Record → background chunk transcription → on stop, combine raw chunks → inject at cursor → enhance in background.
///
/// Background loop every ~25s: transcribe audio chunk → store raw text.
/// On stop: drain remaining chunks → combine all raw text → inject immediately → enhance (non-blocking).
/// User sees "Listening..." while recording, then raw text appears instantly, enhanced version offered after.
@MainActor
final class TranscribeService: ObservableObject {
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

    /// How often to transcribe a chunk (seconds)
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
        promptTask?.cancel()
        promptTask = nil
        rawChunks = []
        rawText = ""
        cleanText = ""
        enhancedText = ""
        suggestedPrompts = []
        sessionDialog = []
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
        guard haikuSessionPrimed, let sessionId = haikuSessionId else { return }
        guard let provider = sessionContextProvider else { return }

        let freshContext = provider()
        let freshHash = freshContext.hashValue
        guard freshHash != lastSessionContextHash, !freshContext.isEmpty else { return }
        lastSessionContextHash = freshHash

        let tempo = estimateTempo()
        DebugLog.log("[PrePrompt] JSONL changed, refreshing predictions... tempo: \(tempo.label)")
        isGeneratingPrompt = true
        defer {
            isGeneratingPrompt = false
            lastRefreshTime = Date()
        }

        let dialogHint = AppSettings.shared.theaterMode
            ? " (predictions + dialog). Dialog: exactly \(tempo.dialogTurns) lines — session is \(tempo.rawValue), keep it tight."
            : ""
        let followUp = "Session activity update:\n\(String(freshContext.suffix(800)))\n\nReply with ONLY the JSON object\(dialogHint), nothing else."

        do {
            let result = try await callClaudeCLI(prompt: followUp, model: "haiku", sessionId: sessionId, resume: true)
            parsePrePromptResult(result)
            DebugLog.log("[PrePrompt] Refresh completed successfully")
        } catch {
            DebugLog.log("[PrePrompt] Refresh failed: \(error)")
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
    }

    /// Generate contextual prompt suggestions based on project + session + active app.
    /// Uses a persistent Haiku session — context loaded once, predictions are lightweight follow-ups.
    /// Returns 2 suggestions so the user can pick the most relevant one.
    func generatePrePrompt() {
        // Sync theme from settings
        dialogTheme = DialogTheme.find(AppSettings.shared.dialogThemeId)

        // Need context to generate a suggestion
        guard !projectContext.isEmpty || !sessionContext.isEmpty else {
            DebugLog.log("[PrePrompt] SKIP — projectContext: \(projectContext.count) chars, sessionContext: \(sessionContext.count) chars")
            return
        }

        promptTask?.cancel()
        suggestedPrompts = []
        isGeneratingPrompt = true
        DebugLog.log("[PrePrompt] STARTED — project: \(projectContext.count) chars, session: \(sessionContext.count) chars, app: \(activeApp), haiku session: \(haikuSessionId ?? "new")")

        promptTask = Task { @MainActor in
            defer {
                isGeneratingPrompt = false
                DebugLog.log("[PrePrompt] DONE — \(suggestedPrompts.count) suggestions")
            }

            do {
                // First call: prime the session with full context
                if !haikuSessionPrimed {
                    let sessionId = UUID().uuidString
                    haikuSessionId = sessionId

                    var contextBlock = ""
                    if !projectContext.isEmpty {
                        contextBlock += "PROJECT:\n\(projectContext)\n\n"
                    }
                    if !sessionContext.isEmpty {
                        contextBlock += "SESSION:\n\(sessionContext)\n\n"
                    }
                    contextBlock += "Active app: \(activeApp)"

                    let theaterOn = AppSettings.shared.theaterMode
                    let dialogInstructions: String
                    if theaterOn {
                        let initialTurns = estimateTempo().dialogTurns
                    dialogInstructions = """
                        2. Write a SHORT COHERENT CONVERSATION between \(dialogTheme.char1) and \(dialogTheme.char2) from \(dialogTheme.show) about what's happening in SESSION. \(dialogTheme.style)
                           - This is a FLOWING DIALOG — each line responds to the previous one. One character brings up what happened, the other reacts, they dig in, explain terms to each other, and reach a conclusion. NOT a list of disconnected observations.
                           - Dialog is ONLY between \(dialogTheme.char1) and \(dialogTheme.char2). When referencing the user, call them "\(dialogTheme.boss)" (from \(dialogTheme.show)).
                           - ELI5: a non-programmer overhearing this conversation should understand what's going on and learn something.
                           - When a technical term comes up, one character explains it naturally in-character. The other reacts. e.g. "A DispatchSource — it's basically a file stalker." / "So... it watches files? Like my ex watches my Instagram?"
                           - Exactly \(initialTurns) lines for this exchange. I'll tell you how many lines to write each time based on session pace — follow it precisely. Build a narrative arc within the given line count.
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
                    You are a parallel AI session that tracks what a developer is doing. You have two jobs:
                    1. Predict what the user will TELL CLAUDE to do next. Read the SESSION carefully — understand the arc of what they're building, what just got completed, and what logically follows. These are voice commands spoken to an AI assistant.
                       INTENT SIGNALS: Look at the user's last 2-3 messages. If they just finished feature X, they'll want to: connect X to the rest of the system, handle edge cases in X, or move to the next feature Y that depends on X. If they hit a bug, they'll want to fix the root cause, not "test again".
                       GOOD: "wire the new sprite animations to the dialog state", "add error handling for when the TTS sidecar fails to connect", "refactor the voice map into a config file so users can customize it"
                       BAD: "test the app", "verify it works", "run the build", "check for errors", "are the predictions accurate?", "does the TTS work now?" — questions and chores are NOT predictions. The user never ASKS Claude to test or evaluate — they TELL Claude to BUILD. Every prediction must be an imperative command starting with a verb.
                    \(dialogInstructions)
                    \(personalityGuide)

                    \(contextBlock)

                    PROJECT is what this project is about. SESSION is the live conversation between the user and Claude — user messages, Claude's responses, tool calls, everything happening right now.
                    You will be asked repeatedly for updated recommendations\(theaterOn ? " + dialog" : "").

                    RULES:
                    - Reply with ONLY a JSON object, nothing else. No markdown, no explanation.
                    - Format: \(formatExample)
                    - Predictions: under 100 chars each. These are IMPERATIVE COMMANDS the user would speak to Claude — always start with a verb (add, wire, refactor, fix, implement, move, connect, update). NEVER a question, observation, or meta-comment about the system. Read the last few SESSION messages — what would the user naturally TELL Claude to build next? Reference actual file names, feature names, and variable names from the session.
                    \(theaterOn ? "- Dialog: a COHERENT back-and-forth conversation. \(dialogTheme.char1) and \(dialogTheme.char2) discuss what just happened, building on each other's lines. STAY IN CHARACTER — use the voice guide above for tone, catchphrases, and analogies. Map technical concepts to the show's universe. Refer to the user as \(dialogTheme.boss). Each line under 120 chars. IMPORTANT: I will specify the exact number of dialog lines each time — follow it precisely. The count is based on session pace so the dialog finishes before the next update arrives." : "")
                    - If SESSION is empty or unclear, \(theaterOn ? "dialog can be about the project in general." : "base recommendations on PROJECT context.")
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
            dialogVoice.speak(dialog, theme: dialogTheme)
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

        // Include pre-prompt prediction for continuity (same "thread" of understanding)
        var predictionHint = ""
        if !suggestedPrompt.isEmpty {
            predictionHint = "\nPredicted intent: \(suggestedPrompt)\n"
        }

        let prompt: String
        if contextBlock.isEmpty && predictionHint.isEmpty {
            prompt = """
            Rewrite this dictated text to be better. Keep the user's voice and meaning. \
            Make it sharper and clearer. If it's already good, return it mostly as-is. \
            Tone: \(appContext). Active app: \(app). \
            Return ONLY the improved text, nothing else.

            "\(text)"
            """
        } else {
            prompt = """
            Enhance this dictated text. You have full context of what the user is working on. \
            Be PROACTIVE — don't just clean up grammar: \
            - Add specific details from the project/session context (file names, function names, variable names) \
            - If the user is giving an instruction, make it more complete and actionable \
            - If the user is describing a problem, add technical specifics they might have skipped while speaking \
            - If the user mentions something vague, fill in the concrete details from context \
            Keep their voice and intent, but make it the version they WISH they'd said. \
            Tone: \(appContext). Active app: \(app).
            \(contextBlock)\(predictionHint)
            Return ONLY the enhanced text, nothing else.

            "\(text)"
            """
        }

        do {
            let result = try await callClaudeCLI(prompt: prompt, model: provider.modelFlag)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
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
                var args = ["--model", model, "-p", prompt, "--output-format", "text", "--dangerously-skip-permissions"]
                if let sid = sessionId {
                    if resume {
                        args += ["--resume", sid]
                    } else {
                        args += ["--session-id", sid]
                    }
                }
                process.arguments = args

                let homePath = home.path
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = homePath
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
