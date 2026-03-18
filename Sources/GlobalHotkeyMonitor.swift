import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.autoclaw.app", category: "Hotkey")

/// Monitors for global hotkeys to control sessions.
/// - Double-tap Right Option (⌥): toggle session on/off (always works on macOS Sequoia)
/// - Single Fn tap: pause/unpause session (only if System Settings > Keyboard > "Press fn key to" = "Do Nothing")
/// - Fn + Space: end session
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

    // Fn tracking
    private var fnDown = false
    private var fnConsumed = false  // set when Fn+Space fires, suppresses pause on Fn release

    // Double-tap tracking (Right Option key)
    private var lastRightOptionUpTime: CFAbsoluteTime = 0
    private var rightOptionDown = false
    private let doubleTapWindow: CFAbsoluteTime = 0.35

    // Debounce
    private var lastToggleTime: CFAbsoluteTime = 0
    private var lastPauseTime: CFAbsoluteTime = 0
    private var lastEndTime: CFAbsoluteTime = 0

    init(onToggle: @escaping () -> Void, onPause: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onPause = onPause
        self.onEnd = onEnd
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
            return
        }

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

        // --- Double-tap Right Option (keyCode 61 = kVK_RightOption) ---
        if keyCode == 61 {
            let optionPressed = flags.contains(.maskAlternate)
            if optionPressed && !rightOptionDown {
                rightOptionDown = true
            } else if !optionPressed && rightOptionDown {
                rightOptionDown = false
                let otherMods: CGEventFlags = [.maskShift, .maskControl, .maskCommand]
                if flags.intersection(otherMods).isEmpty {
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastRightOptionUpTime < doubleTapWindow {
                        lastRightOptionUpTime = 0
                        fireToggle(source: "Double-tap Right ⌥ (CGEvent)")
                    } else {
                        lastRightOptionUpTime = now
                    }
                }
            }
        }
    }

    private func handleCGKeyDown(keyCode: Int64, flags: CGEventFlags) {
        // Space = keyCode 49, while Fn is held
        if keyCode == 49 && fnDown {
            fnConsumed = true
            fireEnd(source: "Fn+Space (CGEvent)")
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

        // --- Double-tap Right Option (keyCode 61) ---
        if event.keyCode == 61 {
            let optionPressed = event.modifierFlags.contains(.option)
            if optionPressed && !rightOptionDown {
                rightOptionDown = true
            } else if !optionPressed && rightOptionDown {
                rightOptionDown = false
                let otherMods: NSEvent.ModifierFlags = [.shift, .control, .command]
                if event.modifierFlags.intersection(otherMods).isEmpty {
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastRightOptionUpTime < doubleTapWindow {
                        lastRightOptionUpTime = 0
                        fireToggle(source: "Double-tap Right ⌥ (NSEvent)")
                    } else {
                        lastRightOptionUpTime = now
                    }
                }
            }
        }
    }

    private func handleNSKeyDown(_ event: NSEvent) {
        // Space = keyCode 49, while Fn is held
        if event.keyCode == 49 && fnDown {
            fnConsumed = true
            fireEnd(source: "Fn+Space (NSEvent)")
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
