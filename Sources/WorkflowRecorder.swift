import SwiftUI
import Combine
import AppKit

/// Records user activity (app switches, clipboard, screenshots) into a WorkflowRecording.
/// Reuses existing ActiveWindowService and ClipboardMonitor — no new system permissions needed.
@MainActor
final class WorkflowRecorder: ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var events: [WorkflowEvent] = []
    @Published var elapsed: TimeInterval = 0

    // MARK: - Private

    private var recording: WorkflowRecording?
    private var startTime: Date?
    private var elapsedTimer: Timer?
    private var screenshotTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Track last seen values to detect changes
    private var lastApp = ""
    private var lastWindow = ""
    private var lastClipboard = ""

    // MARK: - Start / Stop

    func startRecording(projectId: UUID) {
        guard !isRecording else { return }

        recording = WorkflowRecording(projectId: projectId)
        events = []
        elapsed = 0
        startTime = Date()
        isRecording = true
        lastApp = ""
        lastWindow = ""
        lastClipboard = ""

        // Elapsed timer — update every second
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }

        // Periodic screenshot timer — every 30 seconds
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.capturePeriodicScreenshot()
            }
        }

        print("[WorkflowRecorder] Recording started for project \(projectId)")
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

        print("[WorkflowRecorder] Recording stopped — \(events.count) events, \(String(format: "%.0f", elapsed))s")
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

        print("[WorkflowRecorder] Recording discarded")
    }

    // MARK: - Event Capture (called by AppState when forwarding monitor changes)

    /// Called when the active app/window changes
    func recordAppSwitch(app: String, window: String, url: String = "") {
        guard isRecording, !app.isEmpty else { return }
        // Skip if same app+window
        guard app != lastApp || window != lastWindow else { return }
        lastApp = app
        lastWindow = window

        let screenshotPath = captureScreenshot()
        var desc = "Switched to \(app)"
        if !window.isEmpty { desc += " — \(window)" }
        if !url.isEmpty { desc += " (\(url))" }

        let event = WorkflowEvent(
            type: .appSwitch,
            app: app,
            window: window,
            description: desc,
            data: url.isEmpty ? nil : url,  // store URL in data field
            screenshotPath: screenshotPath,
            elapsed: currentElapsed
        )
        appendEvent(event)
    }

    /// Called when clipboard content changes
    func recordClipboardChange(content: String, app: String, window: String) {
        guard isRecording, !content.isEmpty else { return }
        // Skip duplicate clipboard
        guard content != lastClipboard else { return }
        lastClipboard = content

        let screenshotPath = captureScreenshot()
        let preview = String(content.prefix(120))
        let event = WorkflowEvent(
            type: .clipboard,
            app: app,
            window: window,
            description: "Copied text from \(app)",
            data: preview,
            screenshotPath: screenshotPath,
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
        print("[WorkflowRecorder] Event #\(events.count): \(event.type.rawValue) — \(event.description)")
    }

    private func capturePeriodicScreenshot() {
        guard isRecording else { return }
        let screenshotPath = captureScreenshot()
        guard let path = screenshotPath else { return }

        let event = WorkflowEvent(
            type: .screenshot,
            app: lastApp,
            window: lastWindow,
            description: "Screen capture",
            screenshotPath: path,
            elapsed: currentElapsed
        )
        appendEvent(event)
    }

    // MARK: - Screenshot Capture (reuses AppState's pattern)

    private func captureScreenshot() -> String? {
        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else { return nil }

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let maxW: CGFloat = 1024
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
        let filename = "autoclaw_learn_\(UUID().uuidString.prefix(8)).jpg"
        let path = (tmpDir as NSString).appendingPathComponent(filename)

        do {
            try jpegData.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    /// Elapsed time formatted as "M:SS"
    var elapsedFormatted: String {
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%d:%02d", m, s)
    }
}
