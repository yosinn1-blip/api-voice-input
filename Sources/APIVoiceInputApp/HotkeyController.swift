import Carbon
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
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

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }
}
