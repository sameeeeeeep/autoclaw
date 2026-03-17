import AppKit
import Carbon.HIToolbox

final class GlobalHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onToggle: () -> Void
    private var fnDown = false

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        // Fn is a modifier key — fires as flagsChanged, not keyDown
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

            if type == .flagsChanged {
                let flags = event.flags
                let fnPressed = flags.contains(.maskSecondaryFn)

                if fnPressed && !monitor.fnDown {
                    monitor.fnDown = true
                } else if !fnPressed && monitor.fnDown {
                    monitor.fnDown = false
                    // Only fire on clean Fn tap (no other modifiers held)
                    let otherMods: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
                    if flags.intersection(otherMods).isEmpty {
                        DispatchQueue.main.async {
                            monitor.onToggle()
                        }
                    }
                }
            }

            return Unmanaged.passRetained(event)
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
            print("[Autoclaw] Failed to create event tap — grant Accessibility permission in System Settings > Privacy & Security > Accessibility")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        print("[Autoclaw] Global Fn hotkey active")
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
