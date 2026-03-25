import SwiftUI
import Combine
import AppKit

/// Records user activity (app switches, clipboard, clicks, screenshots) into a WorkflowRecording.
/// Uses ScreenCaptureStream for a rolling frame buffer — click events get OCR'd from the pre-click frame.
@MainActor
final class WorkflowRecorder: ObservableObject {

    // MARK: - Recording Modes

    enum RecordingMode {
        case explicit   // user-initiated learn mode (full capture: screen, OCR, clicks)
        case passive    // always-on during sessions (lightweight: app switches, clipboard, files only)
    }

    // MARK: - Published State

    @Published var isRecording = false
    @Published var events: [WorkflowEvent] = []
    @Published var elapsed: TimeInterval = 0
    @Published var recordingMode: RecordingMode = .explicit

    /// Whether passive observation is active (runs during all sessions)
    @Published var isPassiveObserving = false

    // MARK: - Private

    private var recording: WorkflowRecording?
    private var startTime: Date?
    private var elapsedTimer: Timer?
    private var screenshotTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Passive mode buffer — lightweight event log for friction detection
    private var passiveEvents: [WorkflowEvent] = []
    private static let passiveBufferSize = 200

    // Screen capture stream with rolling frame buffer — lazy to avoid permission prompt on launch
    lazy var captureStream = ScreenCaptureStream()

    // Track last seen values to detect changes
    private var lastApp = ""
    private var lastWindow = ""
    private var lastClipboard = ""

    // MARK: - Start / Stop

    /// Start recording. Pass the resolved app name (e.g. "Gmail" not "Google Chrome")
    /// so clicks captured before the first app switch event have the correct app context.
    func startRecording(projectId: UUID, resolvedApp: String? = nil, resolvedWindow: String? = nil) {
        guard !isRecording else { return }

        recording = WorkflowRecording(projectId: projectId)
        events = []
        elapsed = 0
        startTime = Date()
        isRecording = true
        lastClipboard = ""

        // Seed with resolved app name if provided, otherwise fall back to NSWorkspace
        if let resolved = resolvedApp, !resolved.isEmpty {
            lastApp = resolved
            lastWindow = resolvedWindow ?? ""
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            lastApp = frontApp.localizedName ?? ""
            lastWindow = ""
        } else {
            lastApp = ""
            lastWindow = ""
        }

        // Elapsed timer — update every second
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }

        // Periodic screenshot timer — every 30 seconds (fallback for gaps between clicks)
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.capturePeriodicScreenshot()
            }
        }

        // Start the screen capture stream (frame buffer + click monitor)
        Task {
            await captureStream.start()
        }

        // Wire up click events → record with OCR
        captureStream.onClickCaptured = { [weak self] frame, cursorLocation, screenSize in
            self?.recordClick(frame: frame, cursorLocation: cursorLocation, screenSize: screenSize)
        }

        DebugLog.log("[WorkflowRecorder] Recording started for project \(projectId)")
    }

    func stopRecording() -> WorkflowRecording? {
        guard isRecording, var rec = recording else { return nil }

        isRecording = false
        rec.stoppedAt = Date()
        rec.events = events

        elapsedTimer?.invalidate()
        elapsedTimer = nil
        screenshotTimer?.invalidate()
        screenshotTimer = nil
        cancellables.removeAll()

        // Stop the capture stream
        captureStream.onClickCaptured = nil
        captureStream.stop()

        DebugLog.log("[WorkflowRecorder] Recording stopped — \(events.count) events, \(String(format: "%.0f", elapsed))s")
        return rec
    }

    func discardRecording() {
        isRecording = false
        recording = nil
        events = []
        elapsed = 0
        startTime = nil

        elapsedTimer?.invalidate()
        elapsedTimer = nil
        screenshotTimer?.invalidate()
        screenshotTimer = nil
        cancellables.removeAll()

        captureStream.onClickCaptured = nil
        captureStream.stop()

        DebugLog.log("[WorkflowRecorder] Recording discarded")
    }

    // MARK: - Passive Observation (always-on during sessions)

    /// Start lightweight passive observation — no screen capture, just events
    func startPassiveObserving(projectId: UUID) {
        guard !isPassiveObserving else { return }
        isPassiveObserving = true
        passiveEvents = []
        DebugLog.log("[WorkflowRecorder] Passive observation started")
    }

    func stopPassiveObserving() {
        isPassiveObserving = false
        DebugLog.log("[WorkflowRecorder] Passive observation stopped (\(passiveEvents.count) events)")
    }

    /// Get passive events for friction detection analysis
    var recentPassiveEvents: [WorkflowEvent] {
        Array(passiveEvents.suffix(50))
    }

    private func appendPassiveEvent(_ event: WorkflowEvent) {
        passiveEvents.append(event)
        if passiveEvents.count > Self.passiveBufferSize {
            passiveEvents.removeFirst(passiveEvents.count - Self.passiveBufferSize)
        }
    }

    // MARK: - Event Capture (called by AppState when forwarding monitor changes)

    /// Called when the active app/window changes — uses stream's latest frame for OCR
    func recordAppSwitch(app: String, window: String, url: String = "") {
        guard !app.isEmpty else { return }
        guard app != lastApp || window != lastWindow else { return }
        lastApp = app
        lastWindow = window

        var desc = "Switched to \(app)"
        if !window.isEmpty { desc += " — \(window)" }
        if !url.isEmpty { desc += " (\(url))" }

        // Only do OCR in explicit recording mode (expensive)
        let ocrContext = isRecording ? ocrFromStreamFrame() : nil

        let event = WorkflowEvent(
            type: .appSwitch,
            app: app,
            window: window,
            description: desc,
            data: url.isEmpty ? nil : url,
            ocrContext: ocrContext,
            elapsed: currentElapsed
        )

        // Feed both explicit recording and passive observation
        if isRecording { appendEvent(event) }
        if isPassiveObserving { appendPassiveEvent(event) }
    }

    /// Called when clipboard content changes — uses stream's latest frame for OCR
    func recordClipboardChange(content: String, app: String, window: String) {
        guard !content.isEmpty else { return }
        guard content != lastClipboard else { return }
        lastClipboard = content

        let preview = String(content.prefix(120))
        let ocrContext = isRecording ? ocrFromStreamFrame() : nil

        let event = WorkflowEvent(
            type: .clipboard,
            app: app,
            window: window,
            description: "Copied text from \(app)",
            data: preview,
            ocrContext: ocrContext,
            elapsed: currentElapsed
        )

        if isRecording { appendEvent(event) }
        if isPassiveObserving { appendPassiveEvent(event) }
    }

    /// Called by ScreenCaptureStream when a mouse click is detected — OCR the pre-click frame
    func recordClick(frame: CGImage, cursorLocation: CGPoint, screenSize: CGSize) {
        guard isRecording else { return }

        let observations = ScreenOCR.recognizeText(
            in: frame,
            cursorLocation: cursorLocation,
            imageSize: screenSize
        )
        let ocrContext = ScreenOCR.buildContext(from: observations)

        // Identify what was clicked from the nearest text
        let clickTarget: String
        if let nearest = observations.first, nearest.distanceToCursor <= 0.08 {
            clickTarget = "Clicked '\(nearest.text)'"
        } else if let nearest = observations.first {
            clickTarget = "Clicked near '\(nearest.text)'"
        } else {
            clickTarget = "Clicked"
        }

        let desc = "\(clickTarget) in \(lastApp.isEmpty ? "unknown app" : lastApp)"

        let event = WorkflowEvent(
            type: .click,
            app: lastApp,
            window: lastWindow,
            description: desc,
            ocrContext: ocrContext,
            elapsed: currentElapsed
        )
        appendEvent(event)
    }

    // MARK: - Internal

    private var currentElapsed: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private func appendEvent(_ event: WorkflowEvent) {
        events.append(event)
        var logLine = "[WorkflowRecorder] Event #\(events.count): \(event.type.rawValue) — \(event.description)"
        if let ocr = event.ocrContext, !ocr.isEmpty {
            logLine += "\n  OCR: \(String(ocr.prefix(200)))"
        } else {
            logLine += " [no OCR]"
        }
        DebugLog.log(logLine)
    }

    /// Run OCR on the stream's latest buffered frame (for non-click events like app switch, clipboard)
    private func ocrFromStreamFrame() -> String? {
        guard let frame = captureStream.latestFrame() else { return nil }
        let cursorLocation = NSEvent.mouseLocation
        let screenSize: CGSize
        if let mainScreen = NSScreen.main {
            screenSize = mainScreen.frame.size
        } else {
            screenSize = CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
        }

        let observations = ScreenOCR.recognizeText(
            in: frame,
            cursorLocation: cursorLocation,
            imageSize: screenSize
        )
        return ScreenOCR.buildContext(from: observations)
    }

    /// Periodic screenshot with OCR — fallback for capturing state between interactions
    private func capturePeriodicScreenshot() {
        guard isRecording else { return }
        let ocrContext = ocrFromStreamFrame()
        guard ocrContext != nil else { return }  // skip if no frame available

        let event = WorkflowEvent(
            type: .screenshot,
            app: lastApp,
            window: lastWindow,
            description: "Screen capture",
            ocrContext: ocrContext,
            elapsed: currentElapsed
        )
        appendEvent(event)
    }

    /// Elapsed time formatted as "M:SS"
    var elapsedFormatted: String {
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%d:%02d", m, s)
    }
}
