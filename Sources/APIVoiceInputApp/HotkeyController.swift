import Carbon
import CoreGraphics
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var f19HotKeyRef: EventHotKeyRef?
    private var conversationHotKeyRef: EventHotKeyRef?
    private var conversationAltHotKeyRef: EventHotKeyRef?
    private var enterStopHotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var fnEventTap: CFMachPort?
    private var fnRunLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var isRecording = false
    private var lastFnPress = Date.distantPast
    private var fnPressStart = Date.distantPast
    private var f19PressStart = Date.distantPast
    private let onPressed: @Sendable (_ source: String) -> Void

    init(onPressed: @escaping @Sendable (_ source: String) -> Void) {
        self.onPressed = onPressed
    }

    func registerCommandShiftSpace() {
        installCarbonHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        DebugLog.write("register Command+Shift+Space status=\(status)")
    }

    func registerConversationModeHotKey() {
        installCarbonHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 4)
        // F18 = Fn long press via Karabiner; also Cmd+Option+C as fallback
        let statusF18 = RegisterEventHotKey(UInt32(kVK_F18), 0, hotKeyID, GetApplicationEventTarget(), 0, &conversationHotKeyRef)
        let altHotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 5)
        let statusAlt = RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(cmdKey | optionKey), altHotKeyID, GetApplicationEventTarget(), 0, &conversationAltHotKeyRef)
        DebugLog.write("register conversation mode F18=\(statusF18) Cmd+Option+C=\(statusAlt)")
    }

    func registerF19Bridge() {
        installCarbonHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 2)
        let status = RegisterEventHotKey(UInt32(kVK_F19), 0, hotKeyID, GetApplicationEventTarget(), 0, &f19HotKeyRef)
        DebugLog.write("register F19 bridge status=\(status)")
    }

    func setRecordingActive(_ active: Bool) {
        guard isRecording != active else { return }
        isRecording = active
        if active {
            registerEnterStopHotKey()
        } else {
            unregisterEnterStopHotKey()
        }
    }

    @discardableResult
    func registerFnKey() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        DebugLog.write("register direct Fn event tap begin")
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: fnEventTapCallback,
            userInfo: selfPointer
        ) else {
            DebugLog.write("register direct Fn event tap failed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        fnEventTap = tap
        fnRunLoopSource = source
        DebugLog.write("register direct Fn event tap ok")
        return true
    }

    fileprivate func handleCarbonHotKeyPressed(id: UInt32) {
        switch id {
        case 2:
            f19PressStart = Date()
            DebugLog.write("f19 key-down")
        case 3:
            onPressed("enter-stop")
        case 4, 5:
            onPressed("fn-long-press")
        default:
            onPressed("carbon-hotkey")
        }
    }

    fileprivate func handleCarbonHotKeyReleased(id: UInt32) {
        guard id == 2 else { return }
        let duration = Date().timeIntervalSince(f19PressStart)
        let now = Date()
        guard now.timeIntervalSince(lastFnPress) > 0.25 else { return }
        lastFnPress = now
        DebugLog.write("f19 key-up duration=\(String(format: "%.3f", duration))")
        onPressed("f19-hotkey")
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let isFnDown = event.flags.contains(.maskSecondaryFn)
        defer { fnIsDown = isFnDown }

        if isFnDown && !fnIsDown {
            fnPressStart = Date()
        } else if !isFnDown && fnIsDown {
            let duration = Date().timeIntervalSince(fnPressStart)
            let now = Date()
            guard now.timeIntervalSince(lastFnPress) > 0.25 else { return }
            lastFnPress = now
            if duration >= 0.4 {
                onPressed("fn-long-press")
            } else {
                onPressed("direct-fn-eventtap")
            }
        }
    }

    private func installCarbonHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else {
                controller.onPressed("carbon-hotkey")
                return noErr
            }
            let eventKind = GetEventKind(event)
            if eventKind == UInt32(kEventHotKeyReleased) {
                controller.handleCarbonHotKeyReleased(id: hotKeyID.id)
            } else {
                controller.handleCarbonHotKeyPressed(id: hotKeyID.id)
            }
            return noErr
        }, 2, &eventTypes, selfPointer, &handler)
    }

    private func registerEnterStopHotKey() {
        guard enterStopHotKeyRef == nil else { return }
        installCarbonHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4156494E), id: 3)
        let status = RegisterEventHotKey(UInt32(kVK_Return), 0, hotKeyID, GetApplicationEventTarget(), 0, &enterStopHotKeyRef)
        DebugLog.write("register Enter stop hotkey status=\(status)")
    }

    private func unregisterEnterStopHotKey() {
        guard let enterStopHotKeyRef else { return }
        let status = UnregisterEventHotKey(enterStopHotKeyRef)
        DebugLog.write("unregister Enter stop hotkey status=\(status)")
        self.enterStopHotKeyRef = nil
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let f19HotKeyRef {
            UnregisterEventHotKey(f19HotKeyRef)
        }
        if let conversationHotKeyRef {
            UnregisterEventHotKey(conversationHotKeyRef)
        }
        if let conversationAltHotKeyRef {
            UnregisterEventHotKey(conversationAltHotKeyRef)
        }
        if let enterStopHotKeyRef {
            UnregisterEventHotKey(enterStopHotKeyRef)
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
