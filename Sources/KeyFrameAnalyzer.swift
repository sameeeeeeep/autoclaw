import AppKit
import Foundation
import Vision

/// Captures key frames at important moments during a session and uses
/// Claude's vision to build semantic understanding of what the user is doing.
///
/// Instead of relying on noisy OCR text, this analyzes actual screenshots
/// to produce high-level context like "user is browsing design templates on Freepik"
/// or "user is copying data from a Notion table into a Google Sheet."
///
/// Key frames are captured at:
/// - App/web-app switches (what did the user just switch to?)
/// - Clipboard events (what was the user looking at when they copied?)
/// - Click events (what did the user just interact with?)
/// - Periodic intervals during sustained activity (what are they doing right now?)
///
/// Smart features:
/// - Frame differencing: skips captures when the screen hasn't changed
/// - Active window cropping: focuses on the relevant window, not the whole screen
/// - Temporal context: feeds previous analysis into new ones for flow understanding
/// - Dual capture: saves both full-screen and active-window crops for richer analysis
///
/// Analysis is throttled and batched to avoid excessive API calls.
@MainActor
final class KeyFrameAnalyzer: ObservableObject {

    // MARK: - Types

    struct KeyFrame: Identifiable {
        let id = UUID()
        let timestamp: Date
        let trigger: Trigger
        let app: String
        let imagePath: String           // path to saved JPEG (active window crop or full screen)
        let fullScreenPath: String?     // path to full-screen JPEG (when cropped, keeps full for context)
        let windowRect: CGRect?         // active window rect in screen coords (nil = full screen)
        let cursorPosition: CGPoint?    // cursor position at capture time (for click triggers)
        let analysis: String?           // AI-generated description (nil until analyzed)
        let intent: String?             // inferred user intent (nil until analyzed)
    }

    enum Trigger: String {
        case appSwitch       // user switched apps
        case clipboard       // user copied something
        case periodic        // timed capture during sustained activity
        case fileEvent       // file created/modified
        case click           // user clicked (high-signal interaction)
    }

    struct ContextSnapshot {
        let recentFrames: [KeyFrame]
        let currentActivity: String         // AI-synthesized summary of current user activity
        let inferredIntent: String?         // what the user seems to be trying to accomplish
        let involvedApps: [String]
        let workflowStage: String?          // e.g. "researching", "editing", "transferring data"
        let interactionPattern: String?     // e.g. "copy-paste between apps", "comparing documents"
        let uiElements: [String]?           // visible UI elements being interacted with
        let dataTypes: [String]?            // types of data being worked with (text, images, code, etc.)
    }

    // MARK: - State

    @Published var latestContext: ContextSnapshot?
    @Published var isAnalyzing = false

    // MARK: - Configuration

    private static let maxStoredFrames = 30
    private static let analysisCooldown: TimeInterval = 12      // min seconds between analyses
    private static let periodicInterval: TimeInterval = 25      // periodic capture interval
    private static let maxImageWidth = 1440                      // higher res for better analysis
    private static let jpegQuality: CGFloat = 0.7                // higher quality for vision
    private static let changeThreshold: CGFloat = 0.02           // 2% pixel difference = meaningful change
    private static let clickCooldown: TimeInterval = 1.0         // min seconds between click captures

    // MARK: - Private

    private var frames: [KeyFrame] = []
    private var pendingFrames: [KeyFrame] = []   // captured but not yet analyzed
    private var lastAnalysisTime: Date = .distantPast
    private var lastClickCaptureTime: Date = .distantPast
    private var periodicTimer: Timer?
    private var isActive = false
    private var previousAnalysisOutput: String?  // temporal context: feed previous analysis into next

    private let runner: ClaudeCodeRunner
    private let captureStream: ScreenCaptureStream

    init(runner: ClaudeCodeRunner, captureStream: ScreenCaptureStream) {
        self.runner = runner
        self.captureStream = captureStream
    }

    // MARK: - Start / Stop

    func start() {
        guard !isActive else { return }
        isActive = true

        // Periodic capture during sustained activity
        periodicTimer = Timer.scheduledTimer(withTimeInterval: Self.periodicInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame(trigger: .periodic, app: "")
            }
        }

        DebugLog.log("[KeyFrameAnalyzer] Started (change detection + window cropping enabled)")
    }

    func stop() {
        isActive = false
        periodicTimer?.invalidate()
        periodicTimer = nil
        DebugLog.log("[KeyFrameAnalyzer] Stopped (\(frames.count) frames captured)")
    }

    // MARK: - Recent Frames for Sonnet Context

    /// Returns paths to the most recent key frame images.
    /// Attached directly to Sonnet prompts so it can see what the user is doing.
    func recentFramePaths(limit: Int = 5) -> [String] {
        let recent = frames.suffix(limit)
        return recent.map(\.imagePath)
    }

    // MARK: - Capture Triggers

    /// Capture a key frame on app switch
    func onAppSwitch(app: String) {
        captureFrame(trigger: .appSwitch, app: app)
    }

    /// Capture a key frame on clipboard event
    func onClipboard(app: String) {
        captureFrame(trigger: .clipboard, app: app)
    }

    /// Capture a key frame on file event
    func onFileEvent(app: String) {
        captureFrame(trigger: .fileEvent, app: app)
    }

    /// Capture a key frame on user click — high-signal interaction moment
    func onClick(app: String, cursorPosition: CGPoint) {
        guard Date().timeIntervalSince(lastClickCaptureTime) >= Self.clickCooldown else { return }
        lastClickCaptureTime = Date()
        captureFrame(trigger: .click, app: app, cursorPosition: cursorPosition)
    }

    // MARK: - Frame Capture

    private func captureFrame(trigger: Trigger, app: String, cursorPosition: CGPoint? = nil) {
        guard isActive else { return }

        // For periodic captures, check if the screen actually changed
        if trigger == .periodic {
            guard hasScreenChanged() else {
                DebugLog.log("[KeyFrameAnalyzer] Periodic skipped — no visual change")
                return
            }
        }

        // Try active window crop first, fall back to full screen
        var primaryImage: CGImage
        var fullScreenPath: String? = nil
        var windowRect: CGRect? = nil

        if let windowCapture = captureStream.captureActiveWindow() {
            primaryImage = windowCapture.image
            windowRect = windowCapture.windowRect

            // Also save full screen for broader context (lower quality)
            if let fullFrame = captureStream.latestFrame() ?? fallbackCapture() {
                fullScreenPath = saveFrame(fullFrame, quality: 0.4, maxWidth: 1024, suffix: "full")
            }
        } else if let cgImage = captureStream.latestFrame() ?? fallbackCapture() {
            primaryImage = cgImage
        } else {
            return
        }

        // Save the primary image (active window or full screen)
        guard let path = saveFrame(primaryImage) else { return }

        let frame = KeyFrame(
            timestamp: Date(),
            trigger: trigger,
            app: app.isEmpty ? "unknown" : app,
            imagePath: path,
            fullScreenPath: fullScreenPath,
            windowRect: windowRect,
            cursorPosition: cursorPosition,
            analysis: nil,
            intent: nil
        )

        pendingFrames.append(frame)
        frames.append(frame)

        // Trim old frames
        if frames.count > Self.maxStoredFrames {
            let removed = frames.prefix(frames.count - Self.maxStoredFrames)
            for old in removed {
                try? FileManager.default.removeItem(atPath: old.imagePath)
                if let fullPath = old.fullScreenPath {
                    try? FileManager.default.removeItem(atPath: fullPath)
                }
            }
            frames = Array(frames.suffix(Self.maxStoredFrames))
        }

        let cropInfo = windowRect != nil ? " [window crop]" : " [full screen]"
        DebugLog.log("[KeyFrameAnalyzer] Captured frame: \(trigger.rawValue) in \(app)\(cropInfo) (\(pendingFrames.count) pending)")

        // Trigger analysis if we have enough pending frames and cooldown elapsed
        if pendingFrames.count >= 3 || Date().timeIntervalSince(lastAnalysisTime) > Self.analysisCooldown * 2 {
            triggerAnalysis()
        }
    }

    // MARK: - Change Detection (Apple Vision Neural Engine)
    //
    // Ported from video2ai's clip_match.py — uses VNGenerateImageFeaturePrintRequest
    // to embed frames as 768-dim vectors on the Neural Engine (near-zero CPU/memory),
    // then cosine distance to detect meaningful visual state changes.
    // Way more accurate than pixel diffing — understands semantic visual changes.

    /// The last frame's embedding, cached for comparison
    private var lastEmbedding: [Float]?

    /// Rolling buffer of recent embeddings for richer analysis
    private var embeddingBuffer: [[Float]] = []
    private static let embeddingBufferSize = 10

    /// Compare the current frame to the last via Neural Engine embeddings + cosine distance.
    private func hasScreenChanged() -> Bool {
        guard let pair = captureStream.recentFramePair() else {
            return true // no history = assume changed
        }

        guard let currEmb = embedFrame(pair.current) else {
            return true // embedding failed, assume changed
        }

        defer {
            lastEmbedding = currEmb
            embeddingBuffer.append(currEmb)
            if embeddingBuffer.count > Self.embeddingBufferSize {
                embeddingBuffer.removeFirst()
            }
        }

        guard let prevEmb = lastEmbedding else {
            return true // first frame, assume changed
        }

        let distance = cosineDistance(prevEmb, currEmb)
        return distance > Self.changeThreshold
    }

    /// Embed a CGImage using VNGenerateImageFeaturePrintRequest (Neural Engine).
    /// Returns a 768-dim float vector, or nil on failure.
    private func embedFrame(_ image: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            return nil
        }

        // Extract the float vector from the feature print
        let count = result.elementCount
        var vector = [Float](repeating: 0, count: count)
        let data = result.data
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<count {
                vector[i] = floatBuffer[i]
            }
        }

        return vector
    }

    /// Cosine distance between two vectors. Returns 0.0 (identical) to 1.0 (orthogonal).
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> CGFloat {
        guard a.count == b.count, !a.isEmpty else { return 1.0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 1.0 }

        let similarity = dot / denom
        return CGFloat(max(0, 1.0 - similarity))
    }

    /// Detect if this frame represents a significant visual state change
    /// using adaptive thresholding on recent embedding distances (from video2ai).
    func isSignificantChange(for image: CGImage) -> (changed: Bool, distance: CGFloat)? {
        guard let embedding = embedFrame(image) else { return nil }

        guard let prevEmb = lastEmbedding else {
            lastEmbedding = embedding
            return (true, 1.0)
        }

        let distance = cosineDistance(prevEmb, embedding)

        // Adaptive threshold: if we have history, use median + 2*MAD (from video2ai)
        if embeddingBuffer.count >= 3, lastEmbedding != nil {
            var recentDistances: [CGFloat] = []
            for i in 1..<embeddingBuffer.count {
                recentDistances.append(cosineDistance(embeddingBuffer[i-1], embeddingBuffer[i]))
            }
            let sorted = recentDistances.sorted()
            let median = sorted[sorted.count / 2]
            let deviations = recentDistances.map { abs($0 - median) }.sorted()
            let mad = deviations[deviations.count / 2]
            let adaptiveThreshold = max(median + 2.0 * mad, Self.changeThreshold)

            return (distance > adaptiveThreshold, distance)
        }

        return (distance > Self.changeThreshold, distance)
    }

    // MARK: - Image Saving

    private func fallbackCapture() -> CGImage? {
        CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        )
    }

    private func saveFrame(
        _ cgImage: CGImage,
        quality: CGFloat? = nil,
        maxWidth: Int? = nil,
        suffix: String? = nil
    ) -> String? {
        let targetMaxW = CGFloat(maxWidth ?? Self.maxImageWidth)
        let targetQuality = quality ?? Self.jpegQuality

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let scale = srcW > targetMaxW ? targetMaxW / srcW : 1.0
        let dstW = Int(srcW * scale)
        let dstH = Int(srcH * scale)

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: dstW, height: dstH))

        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dstW,
            pixelsHigh: dstH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        nsImage.draw(in: NSRect(x: 0, y: 0, width: dstW, height: dstH))
        NSGraphicsContext.restoreGraphicsState()

        guard let jpegData = resized.representation(using: .jpeg, properties: [.compressionFactor: targetQuality]) else { return nil }

        let tmpDir = NSTemporaryDirectory()
        let sfx = suffix.map { "_\($0)" } ?? ""
        let filename = "autoclaw_keyframe_\(UUID().uuidString.prefix(8))\(sfx).jpg"
        let path = (tmpDir as NSString).appendingPathComponent(filename)

        do {
            try jpegData.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Analysis

    private func triggerAnalysis() {
        guard !isAnalyzing,
              !pendingFrames.isEmpty,
              Date().timeIntervalSince(lastAnalysisTime) >= Self.analysisCooldown else { return }

        isAnalyzing = true
        lastAnalysisTime = Date()
        let framesToAnalyze = pendingFrames
        pendingFrames = []

        Task {
            await analyze(frames: framesToAnalyze)
            self.isAnalyzing = false
        }
    }

    private func analyze(frames framesToAnalyze: [KeyFrame]) async {
        // Build frame descriptions with richer metadata
        let frameDescriptions = framesToAnalyze.map { frame in
            var desc = "[\(frame.trigger.rawValue)] \(frame.app) at \(timeString(frame.timestamp))"
            if let rect = frame.windowRect {
                desc += " (window: \(Int(rect.width))x\(Int(rect.height)))"
            }
            if let cursor = frame.cursorPosition {
                desc += " (click at \(Int(cursor.x)),\(Int(cursor.y)))"
            }
            return desc
        }.joined(separator: "\n")

        // Collect image paths — include both window crops and full-screen context
        var imagePaths: [String] = []
        for frame in framesToAnalyze {
            imagePaths.append(frame.imagePath)
            if let fullPath = frame.fullScreenPath {
                imagePaths.append(fullPath)
            }
        }

        // Build temporal context from previous analysis
        let temporalContext: String
        if let prev = previousAnalysisOutput {
            temporalContext = """

            ## Previous Analysis (for temporal context — understand what changed)
            \(prev)
            """
        } else {
            temporalContext = ""
        }

        let prompt = """
        Analyze these \(framesToAnalyze.count) screenshots captured from a user's macOS session. \
        They were taken at key moments (app switches, clipboard events, clicks, periodic captures). \
        Some images are active-window crops (focused view) and some are full-screen captures (broader context).

        Frame triggers:
        \(frameDescriptions)
        \(temporalContext)

        For each screenshot, describe in detail:
        1. What app/website is shown and what specific page/view/tab is open
        2. What the user is actively doing — be specific about the action (e.g. "editing row 3 of a spreadsheet", not just "using a spreadsheet")
        3. What content is visible — document titles, data values, form fields, button labels, tab names
        4. For click captures: what element the user likely clicked on based on cursor position

        Then synthesize across all frames:
        - **Current Activity**: One detailed sentence describing what the user is doing right now
        - **Intent**: The higher-level goal they seem to be working toward (the why, not the what)
        - **Workflow Stage**: Where they are in their workflow (e.g. "researching", "drafting", "reviewing", "transferring data", "configuring", "debugging")
        - **Interaction Pattern**: How they're working (e.g. "copy-paste between apps", "filling out a form", "comparing two documents side by side", "iterating on a design")
        - **UI Elements**: Key UI elements being interacted with (buttons, menus, panels, fields)
        - **Data Types**: Types of data being worked with (text, code, images, tables, URLs, etc.)
        - **Apps Involved**: List of apps/websites being used

        Respond as JSON:
        {
          "frames": [
            {"description": "...", "app": "...", "action": "...", "visible_content": "..."}
          ],
          "current_activity": "...",
          "intent": "...",
          "workflow_stage": "...",
          "interaction_pattern": "...",
          "ui_elements": ["..."],
          "data_types": ["..."],
          "involved_apps": ["..."]
        }
        """

        do {
            var fullPrompt = prompt
            for path in imagePaths {
                fullPrompt += "\n\nImage: \(path)"
            }

            var output = ""
            for try await chunk in runner.executeDirect(
                prompt: fullPrompt,
                project: Project(id: UUID(), name: "keyframe-analysis", path: NSTemporaryDirectory()),
                model: .sonnet,
                sessionId: nil,
                singleShot: true
            ) {
                output += chunk
            }

            if let context = parseAnalysis(output, framesToAnalyze: framesToAnalyze) {
                latestContext = context
                // Save this analysis as temporal context for the next round
                previousAnalysisOutput = """
                Activity: \(context.currentActivity)
                Intent: \(context.inferredIntent ?? "unknown")
                Stage: \(context.workflowStage ?? "unknown")
                Pattern: \(context.interactionPattern ?? "unknown")
                Apps: \(context.involvedApps.joined(separator: ", "))
                """
                DebugLog.log("[KeyFrameAnalyzer] Analysis complete: \(context.currentActivity)")
            }
        } catch {
            DebugLog.log("[KeyFrameAnalyzer] Analysis failed: \(error)")
        }
    }

    private func parseAnalysis(_ output: String, framesToAnalyze: [KeyFrame]) -> ContextSnapshot? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON
        guard let jsonStart = trimmed.range(of: "{"),
              let jsonEnd = trimmed.range(of: "}", options: .backwards) else {
            return ContextSnapshot(
                recentFrames: framesToAnalyze,
                currentActivity: String(trimmed.prefix(200)),
                inferredIntent: nil,
                involvedApps: framesToAnalyze.map(\.app),
                workflowStage: nil,
                interactionPattern: nil,
                uiElements: nil,
                dataTypes: nil
            )
        }

        let jsonStr = String(trimmed[jsonStart.lowerBound...jsonEnd.upperBound])
        guard let data = jsonStr.data(using: .utf8) else { return nil }

        struct AnalysisResult: Decodable {
            let current_activity: String?
            let intent: String?
            let involved_apps: [String]?
            let workflow_stage: String?
            let interaction_pattern: String?
            let ui_elements: [String]?
            let data_types: [String]?
        }

        guard let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            return ContextSnapshot(
                recentFrames: framesToAnalyze,
                currentActivity: String(trimmed.prefix(200)),
                inferredIntent: nil,
                involvedApps: framesToAnalyze.map(\.app),
                workflowStage: nil,
                interactionPattern: nil,
                uiElements: nil,
                dataTypes: nil
            )
        }

        return ContextSnapshot(
            recentFrames: framesToAnalyze,
            currentActivity: result.current_activity ?? "Unknown activity",
            inferredIntent: result.intent,
            involvedApps: result.involved_apps ?? framesToAnalyze.map(\.app),
            workflowStage: result.workflow_stage,
            interactionPattern: result.interaction_pattern,
            uiElements: result.ui_elements,
            dataTypes: result.data_types
        )
    }

    // MARK: - Query

    /// Get the latest understanding of what the user is doing
    var currentActivity: String? {
        latestContext?.currentActivity
    }

    /// Get the inferred user intent
    var inferredIntent: String? {
        latestContext?.inferredIntent
    }

    /// Get recent frame count
    var frameCount: Int {
        frames.count
    }

    // MARK: - Cleanup

    func cleanup() {
        for frame in frames {
            try? FileManager.default.removeItem(atPath: frame.imagePath)
            if let fullPath = frame.fullScreenPath {
                try? FileManager.default.removeItem(atPath: fullPath)
            }
        }
        frames.removeAll()
        pendingFrames.removeAll()
        previousAnalysisOutput = nil
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
