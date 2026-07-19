import Carbon.HIToolbox
import AppKit

/// One global hot key registered through the Carbon RegisterEventHotKey API —
/// tiny, dependency-free, and it needs no special permissions. Wisp binds
/// ⌥⌘W to toggle the ring. The callback fires on the main thread.
final class HotKey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            me.callback()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x57495350), id: id) // 'WISP'
        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
