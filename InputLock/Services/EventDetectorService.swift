import CoreGraphics
import Foundation

protocol EventDetectorService {
    var lastSwitchShortcutTime: Date? { get }
    func startMonitoring()
    func stopMonitoring()
}

@Observable
final class EventDetectorServiceImpl: EventDetectorService {
    var lastSwitchShortcutTime: Date?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func startMonitoring() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPointer
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }

    let service = Unmanaged<EventDetectorServiceImpl>.fromOpaque(refcon).takeUnretainedValue()

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    let isCtrlSpace = keycode == 49 && flags.contains(.maskControl)
    let isCapsLock = keycode == 57

    if isCtrlSpace || isCapsLock {
        Task { @MainActor in
            service.lastSwitchShortcutTime = Date()
        }
    }

    return Unmanaged.passUnretained(event)
}
