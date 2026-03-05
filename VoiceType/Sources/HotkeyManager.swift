import CoreGraphics
import Foundation

/// Monitors global key events for Ctrl+Shift hold-to-record.
class HotkeyManager {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var ctrlPressed = false
    private var shiftPressed = false
    private var isRecording = false

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        // CGEvent.tapCreate requires a C function pointer. We use a static callback
        // and pass `self` as userInfo.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: HotkeyManager.eventTapCallback,
            userInfo: refcon
        ) else {
            print("VoiceType: Failed to create event tap. Grant Input Monitoring permission in System Settings > Privacy & Security > Input Monitoring.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

        // macOS disables the tap if the callback takes too long. Re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        manager.handleFlagsChanged(event)
        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags

        let newCtrl = flags.contains(.maskControl)
        let newShift = flags.contains(.maskShift)

        // Only react if state actually changed
        guard newCtrl != ctrlPressed || newShift != shiftPressed else { return }
        ctrlPressed = newCtrl
        shiftPressed = newShift

        let comboActive = ctrlPressed && shiftPressed

        if comboActive && !isRecording {
            isRecording = true
            print("[VoiceType] hotkey: record START")
            onRecordStart?()
        } else if !comboActive && isRecording {
            isRecording = false
            print("[VoiceType] hotkey: record STOP")
            onRecordStop?()
        }
    }
}
