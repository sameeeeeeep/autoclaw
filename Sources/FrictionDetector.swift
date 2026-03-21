import Foundation

/// The brain of ARIA's intelligent layer. Watches the live activity stream
/// and matches it against the CapabilityMap to detect moments where
/// AI could eliminate friction the user doesn't even know they have.
///
/// Friction = user doing something manually that a capability could automate.
///
/// Patterns detected:
/// 1. Cross-app data transfer (copy from A, paste in B — but an API could sync)
/// 2. Repetitive navigation (user visits same sequence of pages — could be automated)
/// 3. Manual data entry (typing what could be fetched/generated)
/// 4. File shuttle (download from app A, upload to app B — direct integration exists)
/// 5. Context switching (jumping between apps to reference info — could be surfaced inline)
@MainActor
final class FrictionDetector: ObservableObject {

    // MARK: - Types

    struct FrictionSignal: Identifiable {
        let id = UUID()
        let timestamp: Date
        let pattern: FrictionPattern
        let involvedApps: [String]          // which apps are involved
        let description: String             // human-readable: "You're copying data from Notion to Sheets"
        let capability: CapabilityMap.Capability?  // matched capability, if any
        let suggestion: String              // "I can sync Notion → Sheets automatically"
        let confidence: Double              // 0-1
        let isActionable: Bool              // true if we have a capability to offer
        let matchedWorkflow: SavedWorkflow? // non-nil when pattern == .recognizedWorkflow

        init(timestamp: Date, pattern: FrictionPattern, involvedApps: [String],
             description: String, capability: CapabilityMap.Capability?,
             suggestion: String, confidence: Double, isActionable: Bool,
             matchedWorkflow: SavedWorkflow? = nil) {
            self.timestamp = timestamp
            self.pattern = pattern
            self.involvedApps = involvedApps
            self.description = description
            self.capability = capability
            self.suggestion = suggestion
            self.confidence = confidence
            self.isActionable = isActionable
            self.matchedWorkflow = matchedWorkflow
        }

        /// Whether this should be surfaced to the user
        var shouldSurface: Bool {
            confidence >= 0.6 && isActionable
        }
    }

    enum FrictionPattern: String {
        case crossAppTransfer   // clipboard copy from A → paste in B
        case fileShuttle        // download from A → upload to B
        case repetitiveNav      // same app sequence repeated
        case manualLookup       // switch to app, copy info, switch back
        case repeatedSearch     // searching for same/similar things
        case recognizedWorkflow // matches a previously learned workflow
    }

    // MARK: - State

    @Published var activeFriction: FrictionSignal?    // current friction to surface
    @Published var recentSignals: [FrictionSignal] = []

    /// Callback when friction is detected that should be surfaced to user
    var onFrictionDetected: ((FrictionSignal) -> Void)?

    // MARK: - Dependencies

    private let capabilityMap: CapabilityMap

    /// Optional key frame analyzer for richer context
    var keyFrameAnalyzer: KeyFrameAnalyzer?

    /// Workflow matcher for recognizing learned workflows in passive activity
    var workflowMatcher: WorkflowMatcher?

    /// Saved workflows to match against (updated by AppState when workflows change)
    var savedWorkflows: [SavedWorkflow] = []

    // MARK: - Activity Buffer

    /// Rolling buffer of recent activity for pattern matching
    private var activityBuffer: [ActivityEvent] = []
    private static let bufferSize = 100
    private static let cooldownInterval: TimeInterval = 120  // don't re-suggest same pattern within 2 min
    private var lastSurfacedPatterns: [String: Date] = [:]    // pattern key → last surfaced time

    struct ActivityEvent {
        let timestamp: Date
        let type: ActivityType
        let app: String           // resolved app name (from WebAppResolver or native app)
        let section: String?
        let data: String?         // clipboard content, file name, etc.
        let url: String?
    }

    enum ActivityType {
        case appSwitch
        case clipboard
        case fileCreated
        case fileModified
        case click(context: String?)   // OCR context near click
    }

    init(capabilityMap: CapabilityMap) {
        self.capabilityMap = capabilityMap
    }

    // MARK: - Ingest Events

    /// Called by AppState when the user switches apps
    func recordAppSwitch(app: String, section: String?, url: String?) {
        let event = ActivityEvent(
            timestamp: Date(),
            type: .appSwitch,
            app: app,
            section: section,
            data: nil,
            url: url
        )
        appendEvent(event)
        analyzePatterns()
    }

    /// Called by AppState when clipboard changes
    func recordClipboard(content: String, sourceApp: String, sourceSection: String?) {
        let event = ActivityEvent(
            timestamp: Date(),
            type: .clipboard,
            app: sourceApp,
            section: sourceSection,
            data: String(content.prefix(500)),
            url: nil
        )
        appendEvent(event)
        // Don't analyze yet — wait for the paste (app switch after clipboard)
    }

    /// Called by FileActivityMonitor when a file event occurs
    func recordFileEvent(_ fileEvent: FileActivityMonitor.FileEvent) {
        let event = ActivityEvent(
            timestamp: fileEvent.timestamp,
            type: fileEvent.operation == .created ? .fileCreated : .fileModified,
            app: fileEvent.sourceApp ?? "unknown",
            section: nil,
            data: fileEvent.fileName,
            url: nil
        )
        appendEvent(event)
        analyzePatterns()
    }

    /// Called when a click with OCR context happens
    func recordClick(app: String, ocrContext: String?) {
        let event = ActivityEvent(
            timestamp: Date(),
            type: .click(context: ocrContext),
            app: app,
            section: nil,
            data: nil,
            url: nil
        )
        appendEvent(event)
    }

    // MARK: - Pattern Analysis

    private func analyzePatterns() {
        let now = Date()
        let recentWindow: TimeInterval = 60  // look at last 60 seconds

        let recent = activityBuffer.filter { now.timeIntervalSince($0.timestamp) < recentWindow }
        guard recent.count >= 2 else { return }

        // Check learned workflow recognition FIRST (highest value)
        if let signal = detectRecognizedWorkflow(recent) { surfaceIfNew(signal) }

        // Then check heuristic pattern types
        if let signal = detectCrossAppTransfer(recent) { surfaceIfNew(signal) }
        if let signal = detectFileShuttle(recent) { surfaceIfNew(signal) }
        if let signal = detectManualLookup(recent) { surfaceIfNew(signal) }
        if let signal = detectRepetitiveNav() { surfaceIfNew(signal) }
    }

    // MARK: - Pattern Detectors

    /// Detect: clipboard copy in App A → switch to App B
    /// Friction if we have a capability connecting A and B
    private func detectCrossAppTransfer(_ recent: [ActivityEvent]) -> FrictionSignal? {
        // Find clipboard event followed by app switch to different app
        for i in 0..<recent.count - 1 {
            guard case .clipboard = recent[i].type else { continue }

            let sourceApp = recent[i].app
            let clipContent = recent[i].data ?? ""

            // Look for subsequent app switch
            for j in (i + 1)..<recent.count {
                guard case .appSwitch = recent[j].type else { continue }
                let destApp = recent[j].app
                guard destApp != sourceApp else { continue }

                // Do we have a capability that bridges these apps?
                let bridgeCaps = capabilityMap.capabilities(from: sourceApp, to: destApp)
                let contentHint = clipContent.count > 50 ? "data" : "text"

                if let cap = bridgeCaps.first {
                    return FrictionSignal(
                        timestamp: Date(),
                        pattern: .crossAppTransfer,
                        involvedApps: [sourceApp, destApp],
                        description: "Copying \(contentHint) from \(sourceApp) to \(destApp)",
                        capability: cap,
                        suggestion: "I can transfer data between \(sourceApp) and \(destApp) directly using \(cap.provider)",
                        confidence: 0.7,
                        isActionable: cap.isInstalled
                    )
                } else {
                    // No installed capability — but record the friction for discovery
                    return FrictionSignal(
                        timestamp: Date(),
                        pattern: .crossAppTransfer,
                        involvedApps: [sourceApp, destApp],
                        description: "Copying \(contentHint) from \(sourceApp) to \(destApp)",
                        capability: nil,
                        suggestion: "I might be able to connect \(sourceApp) and \(destApp) — want me to check?",
                        confidence: 0.5,
                        isActionable: false
                    )
                }
            }
        }
        return nil
    }

    /// Detect: file created while in App A → app switch to App B (upload/use pattern)
    private func detectFileShuttle(_ recent: [ActivityEvent]) -> FrictionSignal? {
        for i in 0..<recent.count - 1 {
            guard case .fileCreated = recent[i].type else { continue }

            let sourceApp = recent[i].app
            let fileName = recent[i].data ?? "file"

            // Look for subsequent app switch
            for j in (i + 1)..<recent.count {
                guard case .appSwitch = recent[j].type else { continue }
                let destApp = recent[j].app
                guard destApp != sourceApp else { continue }

                let bridgeCaps = capabilityMap.capabilities(from: sourceApp, to: destApp)

                if let cap = bridgeCaps.first {
                    return FrictionSignal(
                        timestamp: Date(),
                        pattern: .fileShuttle,
                        involvedApps: [sourceApp, destApp],
                        description: "Moving '\(fileName)' from \(sourceApp) to \(destApp)",
                        capability: cap,
                        suggestion: "I can move files between \(sourceApp) and \(destApp) directly",
                        confidence: 0.65,
                        isActionable: cap.isInstalled
                    )
                }

                break  // only check the first app switch after file creation
            }
        }
        return nil
    }

    /// Detect: switch to App B → copy something → switch back to App A
    /// Classic "lookup" pattern — user is referencing info from another app
    private func detectManualLookup(_ recent: [ActivityEvent]) -> FrictionSignal? {
        guard recent.count >= 3 else { return nil }

        // Look for pattern: appSwitch(B) → clipboard → appSwitch(A) where A was the previous app
        for i in 0..<recent.count - 2 {
            guard case .appSwitch = recent[i].type else { continue }
            let lookupApp = recent[i].app

            guard case .clipboard = recent[i + 1].type,
                  recent[i + 1].app == lookupApp else { continue }

            guard case .appSwitch = recent[i + 2].type else { continue }
            let returnApp = recent[i + 2].app
            guard returnApp != lookupApp else { continue }

            // Check if we were in returnApp before the lookup
            let priorApps = activityBuffer
                .filter { $0.timestamp < recent[i].timestamp }
                .suffix(3)
                .compactMap { event -> String? in
                    if case .appSwitch = event.type { return event.app }
                    return nil
                }

            if priorApps.contains(returnApp) {
                let readCaps = capabilityMap.capabilities(action: "read", app: lookupApp)
                if let cap = readCaps.first {
                    return FrictionSignal(
                        timestamp: Date(),
                        pattern: .manualLookup,
                        involvedApps: [returnApp, lookupApp],
                        description: "Looking up info from \(lookupApp) while working in \(returnApp)",
                        capability: cap,
                        suggestion: "I can pull info from \(lookupApp) right here — no need to switch",
                        confidence: 0.75,
                        isActionable: cap.isInstalled
                    )
                }
            }
        }
        return nil
    }

    /// Detect: same sequence of apps visited multiple times in a session
    private func detectRepetitiveNav() -> FrictionSignal? {
        let appSwitches = activityBuffer
            .compactMap { event -> String? in
                if case .appSwitch = event.type { return event.app }
                return nil
            }

        guard appSwitches.count >= 6 else { return nil }

        // Look for repeated subsequences of length 2-4
        for seqLen in 2...min(4, appSwitches.count / 2) {
            let recent = Array(appSwitches.suffix(seqLen))
            var repeatCount = 0

            // Count how many times this sequence appears in the buffer
            for start in stride(from: 0, through: appSwitches.count - seqLen, by: 1) {
                let window = Array(appSwitches[start..<start + seqLen])
                if window == recent { repeatCount += 1 }
            }

            if repeatCount >= 3 {
                let sequence = recent.joined(separator: " → ")
                // Check if any of these apps have capabilities
                let appsWithCaps = recent.filter { capabilityMap.hasCapability(for: $0) }

                if !appsWithCaps.isEmpty {
                    return FrictionSignal(
                        timestamp: Date(),
                        pattern: .repetitiveNav,
                        involvedApps: recent,
                        description: "You keep cycling through: \(sequence)",
                        capability: capabilityMap.capabilities(for: appsWithCaps[0]).first,
                        suggestion: "This looks like a repeating workflow. Want me to automate \(sequence)?",
                        confidence: 0.6,
                        isActionable: true
                    )
                }
            }
        }

        return nil
    }

    /// Detect: current passive activity matches a previously learned & saved workflow.
    /// Uses WorkflowMatcher (NLEmbedding similarity) to compare recent activity
    /// against all saved workflows. This is the Kofia-level recognition.
    ///
    /// Guards against false positives:
    /// - Requires at least 5 recent events (enough signal to match meaningfully)
    /// - Requires at least 2 distinct apps involved (single-app activity is too generic)
    /// - High similarity threshold (0.75) — word embeddings produce high scores on generic terms
    /// - Only matches workflows with 3+ steps (trivial workflows match everything)
    private func detectRecognizedWorkflow(_ recent: [ActivityEvent]) -> FrictionSignal? {
        guard let matcher = workflowMatcher, !savedWorkflows.isEmpty else { return nil }
        guard recent.count >= 5 else { return nil }

        // Require at least 2 distinct apps to avoid matching on single-app generic activity
        let distinctApps = Set(recent.map(\.app)).filter { !$0.isEmpty }
        guard distinctApps.count >= 2 else { return nil }

        // Only match against workflows with enough steps to be meaningful
        let meaningfulWorkflows = savedWorkflows.filter { $0.steps.count >= 3 }

        // Convert passive ActivityEvents into WorkflowEvents for the matcher
        let workflowEvents = recent.map { event -> WorkflowEvent in
            let type: WorkflowEventType
            switch event.type {
            case .appSwitch: type = .appSwitch
            case .clipboard: type = .clipboard
            case .click:     type = .click
            default:         type = .appSwitch
            }
            return WorkflowEvent(
                type: type,
                app: event.app,
                window: event.section ?? "",
                description: "\(event.app) \(event.section ?? "") \(event.data ?? "")",
                data: event.data,
                ocrContext: {
                    if case .click(let ctx) = event.type { return ctx }
                    return nil
                }()
            )
        }

        let matches = matcher.findSimilarWorkflows(
            events: workflowEvents,
            savedWorkflows: meaningfulWorkflows,
            topK: 1
        )

        // High threshold — NLEmbedding word-level averaging produces inflated scores
        // on generic app names like "Chrome", "Gmail". 0.75 means genuinely similar.
        guard let best = matches.first, best.score > 0.75 else { return nil }

        let workflow = best.workflow
        let apps = Set(recent.map(\.app)).filter { !$0.isEmpty }

        return FrictionSignal(
            timestamp: Date(),
            pattern: .recognizedWorkflow,
            involvedApps: Array(apps),
            description: "This looks like your '\(workflow.name)' workflow",
            capability: nil,
            suggestion: "I learned this workflow before — want me to run '\(workflow.name)' for you?",
            confidence: min(best.score + 0.1, 0.95),  // boost slightly since it's a learned match
            isActionable: true,
            matchedWorkflow: workflow
        )
    }

    // MARK: - Surfacing

    /// Enrich a friction signal with key frame context if available
    private func enrichWithKeyFrameContext(_ signal: FrictionSignal) -> FrictionSignal {
        guard let analyzer = keyFrameAnalyzer,
              let context = analyzer.latestContext else { return signal }

        // Use the AI-analyzed context to create a richer description
        var enrichedDescription = signal.description
        if let intent = context.inferredIntent {
            enrichedDescription += " (while \(intent))"
        } else {
            enrichedDescription += " — \(context.currentActivity)"
        }
        if let stage = context.workflowStage {
            enrichedDescription += " [\(stage)]"
        }
        if let pattern = context.interactionPattern {
            enrichedDescription += " — pattern: \(pattern)"
        }

        return FrictionSignal(
            timestamp: signal.timestamp,
            pattern: signal.pattern,
            involvedApps: signal.involvedApps,
            description: enrichedDescription,
            capability: signal.capability,
            suggestion: signal.suggestion,
            confidence: min(signal.confidence + 0.1, 1.0),  // boost confidence with visual context
            isActionable: signal.isActionable,
            matchedWorkflow: signal.matchedWorkflow
        )
    }

    private func surfaceIfNew(_ signal: FrictionSignal) {
        // Create a key for this pattern to prevent re-surfacing
        var key = "\(signal.pattern.rawValue):\(signal.involvedApps.sorted().joined(separator: "+"))"
        // For recognized workflows, include the workflow name for specificity
        if let wf = signal.matchedWorkflow {
            key += ":\(wf.name)"
        }

        // Longer cooldown for workflow recognition (10 min) — don't nag
        let cooldown = signal.pattern == .recognizedWorkflow ? 600.0 : Self.cooldownInterval

        // Check cooldown
        if let lastTime = lastSurfacedPatterns[key],
           Date().timeIntervalSince(lastTime) < cooldown {
            return
        }

        // Enrich with key frame visual context if available
        let enriched = enrichWithKeyFrameContext(signal)

        lastSurfacedPatterns[key] = Date()
        recentSignals.append(enriched)

        // Keep buffer bounded
        if recentSignals.count > 20 {
            recentSignals.removeFirst(recentSignals.count - 20)
        }

        if enriched.shouldSurface {
            activeFriction = enriched
            onFrictionDetected?(enriched)
            DebugLog.log("[FrictionDetector] SURFACING: \(enriched.description) → \(enriched.suggestion) (confidence: \(String(format: "%.0f", enriched.confidence * 100))%)")
        } else {
            DebugLog.log("[FrictionDetector] Detected but not surfacing: \(enriched.description) (confidence: \(String(format: "%.0f", enriched.confidence * 100))%, actionable: \(enriched.isActionable))")
        }
    }

    func dismissFriction() {
        activeFriction = nil
    }

    /// Surface a signal from an external source (e.g. KeyFrameAnalyzer Haiku recognition)
    func surfaceExternal(_ signal: FrictionSignal) {
        surfaceIfNew(signal)
    }

    // MARK: - Buffer Management

    private func appendEvent(_ event: ActivityEvent) {
        activityBuffer.append(event)
        if activityBuffer.count > Self.bufferSize {
            activityBuffer.removeFirst(activityBuffer.count - Self.bufferSize)
        }
    }

    /// Get a summary of recent activity for capability discovery searches
    func activitySummary() -> String {
        let recentApps = Set(activityBuffer.suffix(20).map(\.app)).filter { !$0.isEmpty }
        let transfers = activityBuffer.suffix(20).compactMap { event -> String? in
            if case .clipboard = event.type { return event.app }
            return nil
        }

        var parts: [String] = []
        if !recentApps.isEmpty {
            parts.append("Active apps: \(recentApps.joined(separator: ", "))")
        }
        if !transfers.isEmpty {
            parts.append("Clipboard from: \(Set(transfers).joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }
}
