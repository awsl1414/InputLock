import ApplicationServices
import CoreGraphics
import Foundation

protocol EventDetectorService {
    var lastSwitchShortcutTime: Date? { get }
    var isMonitoring: Bool { get }
    func startMonitoring()
    func stopMonitoring()
}

@Observable
final class EventDetectorServiceImpl: EventDetectorService {
    var lastSwitchShortcutTime: Date?
    private(set) var isMonitoring = false

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard AXIsProcessTrusted() else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
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
        isMonitoring = true
    }

    func stopMonitoring() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
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

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = service.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)

    // 只处理 Caps Lock (57) 和 Space (49)，其余直接放行
    guard keycode == 57 || keycode == 49 else {
        return Unmanaged.passUnretained(event)
    }

    if keycode == 49 && event.flags.contains(.maskControl) {
        recordSwitchTime(service)
    } else if keycode == 57 {
        recordSwitchTime(service)
    }

    return Unmanaged.passUnretained(event)
}

private func recordSwitchTime(_ service: EventDetectorServiceImpl) {
    Task { @MainActor in
        service.lastSwitchShortcutTime = Date()
    }
}
