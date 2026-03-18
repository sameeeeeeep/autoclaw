import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.autoclaw.app", category: "Hotkey")

/// Monitors for the global hotkey to toggle sessions.
/// Primary: double-tap Right Option key (always works on macOS Sequoia).
/// Secondary: single Fn tap (only works if System Settings > Keyboard > "Press fn key to" = "Do Nothing").
final class GlobalHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onToggle: () -> Void

    // Fn tracking
    private var fnDown = false

    // Double-tap tracking (Right Option key)
    private var lastRightOptionUpTime: CFAbsoluteTime = 0
    private var rightOptionDown = false
    private let doubleTapWindow: CFAbsoluteTime = 0.35

    // Debounce
    private var lastToggleTime: CFAbsoluteTime = 0

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        startEventTap()
        startNSEventMonitors()
    }

    // MARK: - CGEvent Tap (primary)

    private func startEventTap() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

            // Handle tap being disabled by the system (e.g. after sleep)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            if type == .flagsChanged {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                monitor.handleCGFlagsChanged(flags: event.flags, keyCode: keyCode)
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

    // MARK: - NSEvent Monitor (fallback)

    private func startNSEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsChanged(event)
            return event
        }
        logger.info("NSEvent monitors active — double-tap Right Option (⌥) to toggle session")
    }

    // MARK: - CGEvent handler

    private func handleCGFlagsChanged(flags: CGEventFlags, keyCode: Int64) {
        // --- Fn key (keyCode 63 = kVK_Function) ---
        let fnPressed = flags.contains(.maskSecondaryFn)
        if fnPressed && !fnDown {
            fnDown = true
        } else if !fnPressed && fnDown {
            fnDown = false
            let otherMods: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
            if flags.intersection(otherMods).isEmpty {
                fireToggle(source: "Fn (CGEvent)")
                return
            }
        }

        // --- Double-tap Right Option (keyCode 61 = kVK_RightOption) ---
        if keyCode == 61 { // kVK_RightOption
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

    // MARK: - NSEvent handler

    private func handleNSFlagsChanged(_ event: NSEvent) {
        // --- Fn key ---
        let fnPressed = event.modifierFlags.contains(.function)
        if fnPressed && !fnDown {
            fnDown = true
        } else if !fnPressed && fnDown {
            fnDown = false
            let otherMods: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            if event.modifierFlags.intersection(otherMods).isEmpty {
                fireToggle(source: "Fn (NSEvent)")
                return
            }
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

    /// Debounced toggle to prevent double-fire from both monitors
    private func fireToggle(source: String) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastToggleTime > 0.3 else { return }
        lastToggleTime = now
        logger.info("Hotkey triggered (\(source, privacy: .public))")
        DispatchQueue.main.async { self.onToggle() }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        localMonitor = nil
    }
}
