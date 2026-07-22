import AppKit
import Carbon.HIToolbox

/// Global hot keys registered through the Carbon `RegisterEventHotKey` API —
/// tiny, dependency-free, and needing no special permissions (unlike an
/// `NSEvent` keyboard monitor, which would require Accessibility).
///
/// One shared Carbon event handler dispatches to every registration by id, so
/// rebinding a key is unregister-then-register rather than tearing down the
/// handler. Callbacks arrive on the main thread.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Stable ids for Wisp's bindings.
    enum Binding: UInt32, CaseIterable {
        case toggleRing = 1
        case toggleSpotlight = 2
    }

    private var eventHandler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    private static let signature = OSType(0x57495350) // 'WISP'

    private init() {}

    /// Binds `combo` to `action`, replacing any previous binding for `id`.
    /// Returns false if the combo is unusable — already claimed by the system
    /// or another app, or missing a real modifier.
    @discardableResult
    func register(_ id: Binding, combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        unregister(id)
        guard combo.isValid else { return false }
        guard installHandlerIfNeeded() else { return false }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }

        refs[id.rawValue] = ref
        actions[id.rawValue] = action
        return true
    }

    func unregister(_ id: Binding) {
        if let ref = refs.removeValue(forKey: id.rawValue) {
            UnregisterEventHotKey(ref)
        }
        actions[id.rawValue] = nil
    }

    /// True if the combo can be registered right now — used by the recorder to
    /// reject a shortcut some other app already owns before storing it.
    func isAvailable(_ combo: KeyCombo, excluding id: Binding? = nil) -> Bool {
        guard combo.isValid else { return false }
        // A combo already bound to another Wisp action is a conflict too.
        for binding in Binding.allCases where binding != id {
            if refs[binding.rawValue] != nil, boundCombos[binding.rawValue] == combo {
                return false
            }
        }
        guard installHandlerIfNeeded() else { return false }
        var probe: EventHotKeyRef?
        let probeID = EventHotKeyID(signature: Self.signature, id: 0xFFFF)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, probeID,
                                         GetApplicationEventTarget(), 0, &probe)
        if let probe { UnregisterEventHotKey(probe) }
        return status == noErr
    }

    /// What each id is currently bound to, so `isAvailable` can spot a clash
    /// between Wisp's own two shortcuts.
    private var boundCombos: [UInt32: KeyCombo] = [:]

    func note(_ id: Binding, combo: KeyCombo) {
        boundCombos[id.rawValue] = combo
    }

    private func installHandlerIfNeeded() -> Bool {
        if eventHandler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let got = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard got == noErr, hotKeyID.signature == HotKeyCenter.signature else { return noErr }
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated {
                HotKeyCenter.shared.actions[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        return status == noErr
    }
}
