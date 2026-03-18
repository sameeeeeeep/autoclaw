import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.autoclaw.app", category: "Hotkey")

/// Monitors for global hotkeys to control sessions.
/// - Double-tap Left Option (⌥): end session
/// - Option + Z: screenshot to thread
/// - Single Fn tap: pause/unpause session (only if System Settings > Keyboard > "Press fn key to" = "Do Nothing")
final class GlobalHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalFlagMonitor: Any?
    private var localFlagMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    private var onToggle: () -> Void
    private var onPause: () -> Void
    private var onEnd: () -> Void
    private var onScreenshot: () -> Void
    private var onCycleMode: () -> Void

    // Fn tracking
    private var fnDown = false
    private var fnConsumed = false  // set when Fn+Space fires, suppresses pause on Fn release

    // Double-tap tracking (Left Option key — end session)
    private var lastLeftOptionUpTime: CFAbsoluteTime = 0
    private var leftOptionDown = false
    private var leftOptionConsumed = false  // set when Left⌥+Space fires, suppresses end on release

    private let doubleTapWindow: CFAbsoluteTime = 0.35

    // Debounce
    private var lastToggleTime: CFAbsoluteTime = 0
    private var lastPauseTime: CFAbsoluteTime = 0
    private var lastEndTime: CFAbsoluteTime = 0
    private var lastScreenshotTime: CFAbsoluteTime = 0
    private var lastCycleModeTime: CFAbsoluteTime = 0

    init(onToggle: @escaping () -> Void, onPause: @escaping () -> Void, onEnd: @escaping () -> Void, onScreenshot: @escaping () -> Void = {}, onCycleMode: @escaping () -> Void = {}) {
        self.onToggle = onToggle
        self.onPause = onPause
        self.onEnd = onEnd
        self.onScreenshot = onScreenshot
        self.onCycleMode = onCycleMode
    }

    static func debugLog(_ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [Hotkey] \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/autoclaw_hotkey.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }

    func start() {
        startEventTap()
        startNSEventMonitors()
    }

    // MARK: - CGEvent Tap (primary — flags only)

    private func startEventTap() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            if type == .flagsChanged {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                monitor.handleCGFlagsChanged(flags: event.flags, keyCode: keyCode)
            } else if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                monitor.handleCGKeyDown(keyCode: keyCode, flags: event.flags)
            }

            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap = eventTap else {
            logger.error("CGEvent tap failed — grant Accessibility permission in System Settings > Privacy & Security > Accessibility")
            Self.debugLog("⚠️ CGEvent tap FAILED — grant Accessibility permission")
            return
        }
        Self.debugLog("✅ CGEvent tap created successfully")

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.info("CGEvent tap active")
    }

    // MARK: - NSEvent Monitors (fallback)

    private func startNSEventMonitors() {
        globalFlagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsChanged(event)
        }
        localFlagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsChanged(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSKeyDown(event)
            return event
        }
        logger.info("NSEvent monitors active — double-tap Right Option (⌥) to toggle session")
    }

    // MARK: - CGEvent handlers

    private func handleCGFlagsChanged(flags: CGEventFlags, keyCode: Int64) {
        // --- Fn key (keyCode 63 = kVK_Function) ---
        let fnPressed = flags.contains(.maskSecondaryFn)
        if fnPressed && !fnDown {
            fnDown = true
            fnConsumed = false
        } else if !fnPressed && fnDown {
            fnDown = false
            if !fnConsumed {
                let otherMods: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
                if flags.intersection(otherMods).isEmpty {
                    firePause(source: "Fn (CGEvent)")
                    return
                }
            }
            fnConsumed = false
        }

        // --- Double-tap Left Option (keyCode 58 = kVK_Option) → end session ---
        if keyCode == 58 {
            let optionPressed = flags.contains(.maskAlternate)
            if optionPressed && !leftOptionDown {
                leftOptionDown = true
                leftOptionConsumed = false
            } else if !optionPressed && leftOptionDown {
                leftOptionDown = false
                if !leftOptionConsumed {
                    let otherMods: CGEventFlags = [.maskShift, .maskControl, .maskCommand]
                    if flags.intersection(otherMods).isEmpty {
                        let now = CFAbsoluteTimeGetCurrent()
                        if now - lastLeftOptionUpTime < doubleTapWindow {
                            lastLeftOptionUpTime = 0
                            fireEnd(source: "Double-tap Left ⌥ (CGEvent)")
                        } else {
                            lastLeftOptionUpTime = now
                        }
                    }
                }
                leftOptionConsumed = false
            }
        }
    }

    private func handleCGKeyDown(keyCode: Int64, flags: CGEventFlags) {
        // Option + Z (keyCode 6) → screenshot
        if keyCode == 6 && flags.contains(.maskAlternate) {
            leftOptionConsumed = true
            fireScreenshot(source: "⌥+Z (CGEvent)")
        }
        // Option + X (keyCode 7) → cycle request mode
        if keyCode == 7 && flags.contains(.maskAlternate) {
            leftOptionConsumed = true
            fireCycleMode(source: "⌥+X (CGEvent)")
        }
    }

    // MARK: - NSEvent handlers

    private func handleNSFlagsChanged(_ event: NSEvent) {
        // --- Fn key ---
        let fnPressed = event.modifierFlags.contains(.function)
        if fnPressed && !fnDown {
            fnDown = true
            fnConsumed = false
        } else if !fnPressed && fnDown {
            fnDown = false
            if !fnConsumed {
                let otherMods: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
                if event.modifierFlags.intersection(otherMods).isEmpty {
                    firePause(source: "Fn (NSEvent)")
                    return
                }
            }
            fnConsumed = false
        }

        // --- Double-tap Left Option (keyCode 58) → end session ---
        if event.keyCode == 58 {
            let optionPressed = event.modifierFlags.contains(.option)
            if optionPressed && !leftOptionDown {
                leftOptionDown = true
                leftOptionConsumed = false
            } else if !optionPressed && leftOptionDown {
                leftOptionDown = false
                if !leftOptionConsumed {
                    let otherMods: NSEvent.ModifierFlags = [.shift, .control, .command]
                    if event.modifierFlags.intersection(otherMods).isEmpty {
                        let now = CFAbsoluteTimeGetCurrent()
                        if now - lastLeftOptionUpTime < doubleTapWindow {
                            lastLeftOptionUpTime = 0
                            fireEnd(source: "Double-tap Left ⌥ (NSEvent)")
                        } else {
                            lastLeftOptionUpTime = now
                        }
                    }
                }
                leftOptionConsumed = false
            }
        }
    }

    private func handleNSKeyDown(_ event: NSEvent) {
        // Option + Z (keyCode 6) → screenshot
        if event.keyCode == 6 && event.modifierFlags.contains(.option) {
            leftOptionConsumed = true
            fireScreenshot(source: "⌥+Z (NSEvent)")
        }
        // Option + X (keyCode 7) → cycle request mode
        if event.keyCode == 7 && event.modifierFlags.contains(.option) {
            leftOptionConsumed = true
            fireCycleMode(source: "⌥+X (NSEvent)")
        }
    }

    // MARK: - Debounced actions

    private func fireToggle(source: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastToggleTime > 0.3 else { return }
        lastToggleTime = now
        logger.info("Toggle hotkey (\(source, privacy: .public))")
        DispatchQueue.main.async { self.onToggle() }
    }

    private func firePause(source: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPauseTime > 0.3 else { return }
        lastPauseTime = now
        logger.info("Pause hotkey (\(source, privacy: .public))")
        DispatchQueue.main.async { self.onPause() }
    }

    private func fireEnd(source: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastEndTime > 0.3 else { return }
        lastEndTime = now
        logger.info("End hotkey (\(source, privacy: .public))")
        DispatchQueue.main.async { self.onEnd() }
    }

    private func fireScreenshot(source: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastScreenshotTime > 0.5 else { return }
        lastScreenshotTime = now
        logger.info("Screenshot hotkey (\(source, privacy: .public))")
        DispatchQueue.main.async { self.onScreenshot() }
    }

    private func fireCycleMode(source: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastCycleModeTime > 0.2 else { return }
        lastCycleModeTime = now
        logger.info("Cycle mode hotkey (\(source, privacy: .public))")
        DispatchQueue.main.async { self.onCycleMode() }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let m = globalFlagMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        eventTap = nil
        runLoopSource = nil
        globalFlagMonitor = nil
        localFlagMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
    }
}
