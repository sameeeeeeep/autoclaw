import AppKit
import ScreenCaptureKit
import CoreMedia

/// Manages a low-fps screen capture stream with a rolling frame buffer.
/// Uses ScreenCaptureKit (like autoclawd's SystemAudioCapturer) with permission handling.
/// Falls back to CGWindowListCreateImage if SCK permission is denied.
@MainActor
final class ScreenCaptureStream: NSObject, ObservableObject {

    // MARK: - Public Interface

    /// Called on the main actor when a mouse click is detected.
    var onClickCaptured: ((_ frame: CGImage, _ cursorLocation: CGPoint, _ screenSize: CGSize) -> Void)?

    /// Whether the stream is currently running
    @Published private(set) var isStreaming = false

    // MARK: - Private State

    private var stream: SCStream?
    private var streamOutput: ScreenStreamOutput?
    private var clickMonitor: ClickEventMonitor?
    private var fallbackTimer: Timer?   // only used if SCK is unavailable

    // Rolling frame buffer (last ~2 seconds at 2fps = 4 frames)
    private static let bufferSize = 4
    nonisolated(unsafe) private var frameBuffer: [CGImage] = []
    private let frameLock = NSLock()

    // MARK: - Permission

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Start / Stop

    func start() async {
        guard !isStreaming else { return }

        // Try ScreenCaptureKit first (preferred — hardware accelerated, no polling)
        let sckStarted = await startSCStream()

        if !sckStarted {
            // Fallback: CGWindowListCreateImage timer (already works without new TCC)
            DebugLog.log("[ScreenCaptureStream] SCK unavailable, falling back to CGWindowList timer")
            startFallbackTimer()
        }

        // Start click event monitoring (needs Accessibility permission)
        let monitor = ClickEventMonitor { [weak self] in
            guard let self = self else { return }

            self.frameLock.lock()
            let preClickFrame = self.frameBuffer.last
            self.frameLock.unlock()

            guard let frame = preClickFrame else { return }

            let cursorLocation = NSEvent.mouseLocation
            let screenSize: CGSize
            if let mainScreen = NSScreen.main {
                screenSize = mainScreen.frame.size
            } else {
                screenSize = CGSize(width: frame.width, height: frame.height)
            }

            Task { @MainActor [weak self] in
                self?.onClickCaptured?(frame, cursorLocation, screenSize)
            }
        }
        monitor.start()
        self.clickMonitor = monitor

        isStreaming = true
    }

    func stop() {
        guard isStreaming else { return }

        clickMonitor?.stop()
        clickMonitor = nil

        // Stop SCStream if running
        if let stream = stream {
            stream.stopCapture { _ in }
        }
        stream = nil
        streamOutput = nil

        // Stop fallback timer if running
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        isStreaming = false

        frameLock.lock()
        frameBuffer.removeAll()
        frameLock.unlock()

        DebugLog.log("[ScreenCaptureStream] Stopped")
    }

    /// Get the most recent buffered frame
    func latestFrame() -> CGImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return frameBuffer.last
    }

    // MARK: - ScreenCaptureKit Stream

    private func startSCStream() async -> Bool {
        // Check permission first
        if !Self.hasPermission() {
            Self.requestPermission()
            // Give the user a moment to respond, then check again
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Self.hasPermission() {
                DebugLog.log("[ScreenCaptureStream] Screen Recording permission not granted")
                return false
            }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                DebugLog.log("[ScreenCaptureStream] No display found")
                return false
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.width = 1280
            config.height = 720
            config.minimumFrameInterval = CMTime(value: 1, timescale: 2) // 2 fps
            config.queueDepth = 3
            config.showsCursor = true
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let output = ScreenStreamOutput { [weak self] cgImage in
                self?.bufferFrame(cgImage)
            }
            self.streamOutput = output

            let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try scStream.addStreamOutput(output, type: .screen,
                                         sampleHandlerQueue: .global(qos: .utility))
            try await scStream.startCapture()

            self.stream = scStream
            DebugLog.log("[ScreenCaptureStream] SCStream started (1280x720 @ 2fps)")
            return true
        } catch {
            DebugLog.log("[ScreenCaptureStream] SCStream failed: \(error)")
            return false
        }
    }

    // MARK: - Fallback: CGWindowListCreateImage Timer

    private func startFallbackTimer() {
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFallbackFrame()
            }
        }
        DebugLog.log("[ScreenCaptureStream] Fallback timer started (CGWindowList @ 2fps)")
    }

    private func captureFallbackFrame() {
        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else { return }
        bufferFrame(cgImage)
    }

    // MARK: - Frame Buffer

    private func bufferFrame(_ frame: CGImage) {
        frameLock.lock()
        frameBuffer.append(frame)
        if frameBuffer.count > Self.bufferSize {
            frameBuffer.removeFirst(frameBuffer.count - Self.bufferSize)
        }
        frameLock.unlock()
    }
}

// MARK: - SCStream Output Handler

/// Receives screen frames from SCStream and converts CVPixelBuffer → CGImage.
private class ScreenStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: (CGImage) -> Void

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        let rect = CGRect(x: 0, y: 0,
                          width: CVPixelBufferGetWidth(imageBuffer),
                          height: CVPixelBufferGetHeight(imageBuffer))
        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return }

        onFrame(cgImage)
    }
}

// MARK: - Click Event Monitor

/// Monitors mouse clicks via a passive CGEvent tap on a background thread.
private class ClickEventMonitor {
    private let onClick: () -> Void
    private var thread: Thread?
    private var tap: CFMachPort?
    private var lastClickTime: Date = .distantPast
    private static let debounceInterval: TimeInterval = 0.3

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    func start() {
        let thread = Thread { [weak self] in
            self?.runEventTap()
        }
        thread.name = "ScreenCaptureStream.ClickMonitor"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        thread?.cancel()
        thread = nil
        tap = nil
    }

    private func runEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)

        let unmanagedSelf = Unmanaged.passRetained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<ClickEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handleClick()
                return Unmanaged.passRetained(event)
            },
            userInfo: unmanagedSelf.toOpaque()
        ) else {
            DebugLog.log("[ClickEventMonitor] Failed to create event tap — Accessibility permission needed")
            unmanagedSelf.release()
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        CFRunLoopRun()

        unmanagedSelf.release()
    }

    private func handleClick() {
        let now = Date()
        guard now.timeIntervalSince(lastClickTime) >= Self.debounceInterval else { return }
        lastClickTime = now
        onClick()
    }

    deinit {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}
