import Carbon
import CoreGraphics
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var f19HotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var fnEventTap: CFMachPort?
    private var fnRunLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var lastFnPress = Date.distantPast
    private let onPressed: @Sendable () -> Void

    init(onPressed: @escaping @Sendable () -> Void) {
        self.onPressed = onPressed
    }

    func registerCommandShiftSpace() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.onPressed()
            return noErr
        }, 1, &eventType, selfPointer, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func registerF19Bridge() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 2)
        RegisterEventHotKey(UInt32(kVK_F19), 0, hotKeyID, GetApplicationEventTarget(), 0, &f19HotKeyRef)
    }

    @discardableResult
    func registerFnKey() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: fnEventTapCallback,
            userInfo: selfPointer
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        fnEventTap = tap
        fnRunLoopSource = source
        return true
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let isFnDown = event.flags.contains(.maskSecondaryFn)
        defer { fnIsDown = isFnDown }

        guard isFnDown, fnIsDown == false else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastFnPress) > 0.25 else {
            return
        }
        lastFnPress = now
        onPressed()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let f19HotKeyRef {
            UnregisterEventHotKey(f19HotKeyRef)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
        if let fnRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), fnRunLoopSource, .commonModes)
        }
        if let fnEventTap {
            CFMachPortInvalidate(fnEventTap)
        }
    }
}

private func fnEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .flagsChanged, let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
    controller.handleFlagsChanged(event)
    return Unmanaged.passUnretained(event)
}
