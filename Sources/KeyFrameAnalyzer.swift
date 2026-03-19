import AppKit
import Foundation

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
/// - Periodic intervals during sustained activity (what are they doing right now?)
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
        let imagePath: String       // path to saved JPEG
        let analysis: String?       // AI-generated description (nil until analyzed)
        let intent: String?         // inferred user intent (nil until analyzed)
    }

    enum Trigger: String {
        case appSwitch       // user switched apps
        case clipboard       // user copied something
        case periodic        // timed capture during sustained activity
        case fileEvent       // file created/modified
    }

    struct ContextSnapshot {
        let recentFrames: [KeyFrame]
        let currentActivity: String     // AI-synthesized summary of current user activity
        let inferredIntent: String?     // what the user seems to be trying to accomplish
        let involvedApps: [String]
    }

    // MARK: - State

    @Published var latestContext: ContextSnapshot?
    @Published var isAnalyzing = false

    // MARK: - Configuration

    private static let maxStoredFrames = 20
    private static let analysisCooldown: TimeInterval = 15  // min seconds between analyses
    private static let periodicInterval: TimeInterval = 30  // periodic capture interval
    private static let maxImageWidth = 1024                  // resize captures for efficiency

    // MARK: - Private

    private var frames: [KeyFrame] = []
    private var pendingFrames: [KeyFrame] = []   // captured but not yet analyzed
    private var lastAnalysisTime: Date = .distantPast
    private var periodicTimer: Timer?
    private var isActive = false

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

        DebugLog.log("[KeyFrameAnalyzer] Started")
    }

    func stop() {
        isActive = false
        periodicTimer?.invalidate()
        periodicTimer = nil
        DebugLog.log("[KeyFrameAnalyzer] Stopped (\(frames.count) frames captured)")
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

    // MARK: - Frame Capture

    private func captureFrame(trigger: Trigger, app: String) {
        guard isActive else { return }

        // Get the latest frame from the capture stream
        guard let cgImage = captureStream.latestFrame() ?? fallbackCapture() else { return }

        // Resize and save as JPEG
        guard let path = saveFrame(cgImage) else { return }

        let frame = KeyFrame(
            timestamp: Date(),
            trigger: trigger,
            app: app.isEmpty ? "unknown" : app,
            imagePath: path,
            analysis: nil,
            intent: nil
        )

        pendingFrames.append(frame)
        frames.append(frame)

        // Trim old frames
        if frames.count > Self.maxStoredFrames {
            // Clean up old image files
            let removed = frames.prefix(frames.count - Self.maxStoredFrames)
            for old in removed {
                try? FileManager.default.removeItem(atPath: old.imagePath)
            }
            frames = Array(frames.suffix(Self.maxStoredFrames))
        }

        DebugLog.log("[KeyFrameAnalyzer] Captured frame: \(trigger.rawValue) in \(app) (\(pendingFrames.count) pending)")

        // Trigger analysis if we have enough pending frames and cooldown elapsed
        if pendingFrames.count >= 3 || Date().timeIntervalSince(lastAnalysisTime) > Self.analysisCooldown * 2 {
            triggerAnalysis()
        }
    }

    private func fallbackCapture() -> CGImage? {
        CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        )
    }

    private func saveFrame(_ cgImage: CGImage) -> String? {
        // Resize to maxImageWidth for efficiency
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let maxW = CGFloat(Self.maxImageWidth)
        let scale = srcW > maxW ? maxW / srcW : 1.0
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

        guard let jpegData = resized.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else { return nil }

        let tmpDir = NSTemporaryDirectory()
        let filename = "autoclaw_keyframe_\(UUID().uuidString.prefix(8)).jpg"
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
        // Build a prompt with the key frames
        let frameDescriptions = framesToAnalyze.map { frame in
            "[\(frame.trigger.rawValue)] \(frame.app) at \(timeString(frame.timestamp))"
        }.joined(separator: "\n")

        // Collect image paths for vision
        let imagePaths = framesToAnalyze.map(\.imagePath)

        let prompt = """
        Analyze these \(framesToAnalyze.count) screenshots captured from a user's macOS session. \
        They were taken at key moments (app switches, clipboard events, periodic captures).

        Frame triggers:
        \(frameDescriptions)

        For each screenshot, describe:
        1. What app/website is shown
        2. What the user appears to be doing (specific actions, not vague)
        3. What content is visible (page names, data types, document titles)

        Then synthesize:
        - **Current Activity**: One sentence describing what the user is doing right now
        - **Intent**: What they seem to be trying to accomplish (the goal, not the action)
        - **Apps Involved**: List of apps/websites being used

        Respond as JSON:
        {
          "frames": [
            {"description": "...", "app": "...", "action": "..."}
          ],
          "current_activity": "...",
          "intent": "...",
          "involved_apps": ["..."]
        }
        """

        do {
            // Create a prompt that references the images
            var fullPrompt = prompt
            for path in imagePaths {
                fullPrompt += "\n\nImage: \(path)"
            }

            var output = ""
            for try await chunk in runner.executeDirect(
                prompt: fullPrompt,
                project: Project(id: UUID(), name: "keyframe-analysis", path: NSTemporaryDirectory()),
                model: .haiku,
                sessionId: nil,
                singleShot: true
            ) {
                output += chunk
            }

            if let context = parseAnalysis(output, framesToAnalyze: framesToAnalyze) {
                latestContext = context
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
            // Fallback: use the raw output as the activity description
            return ContextSnapshot(
                recentFrames: framesToAnalyze,
                currentActivity: String(trimmed.prefix(200)),
                inferredIntent: nil,
                involvedApps: framesToAnalyze.map(\.app)
            )
        }

        let jsonStr = String(trimmed[jsonStart.lowerBound...jsonEnd.upperBound])
        guard let data = jsonStr.data(using: .utf8) else { return nil }

        struct AnalysisResult: Decodable {
            let current_activity: String?
            let intent: String?
            let involved_apps: [String]?
        }

        guard let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            return ContextSnapshot(
                recentFrames: framesToAnalyze,
                currentActivity: String(trimmed.prefix(200)),
                inferredIntent: nil,
                involvedApps: framesToAnalyze.map(\.app)
            )
        }

        return ContextSnapshot(
            recentFrames: framesToAnalyze,
            currentActivity: result.current_activity ?? "Unknown activity",
            inferredIntent: result.intent,
            involvedApps: result.involved_apps ?? framesToAnalyze.map(\.app)
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
        }
        frames.removeAll()
        pendingFrames.removeAll()
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
