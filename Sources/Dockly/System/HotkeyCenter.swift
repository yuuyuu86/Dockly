import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon — they work without Accessibility permission,
/// which keeps first-run friction down.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private struct Registration {
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async {
                HotkeyCenter.shared.fire(hkID.id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ id: UInt32) {
        registrations[id]?.handler()
    }

    @discardableResult
    func register(_ hotkey: Hotkey, handler: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x444B4C59), id: id) // 'DKLY'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    func unregisterAll() {
        for (_, r) in registrations { if let ref = r.ref { UnregisterEventHotKey(ref) } }
        registrations.removeAll()
    }

    /// Re-registers every hotkey in the library. Cheap enough to call whenever
    /// profiles change.
    func rebind(store: DocklyStore) {
        unregisterAll()
        for profile in store.library.profiles {
            guard let hk = profile.hotkey else { continue }
            let id = profile.id
            register(hk) { store.activate(id) }
        }
        if let cycle = store.library.settings.cycleHotkey {
            register(cycle) { store.cycle(by: 1) }
        }
    }
}

// MARK: - Recording a shortcut

/// A tiny NSView that captures the next key combination the user presses.
final class HotkeyRecorderView: NSView {
    var onCapture: ((Hotkey) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }   // esc
        var carbon: UInt32 = 0
        let f = event.modifierFlags
        if f.contains(.command) { carbon |= UInt32(cmdKey) }
        if f.contains(.option)  { carbon |= UInt32(optionKey) }
        if f.contains(.control) { carbon |= UInt32(controlKey) }
        if f.contains(.shift)   { carbon |= UInt32(shiftKey) }
        guard carbon != 0 else { NSSound.beep(); return }
        onCapture?(Hotkey(keyCode: UInt32(event.keyCode), modifiers: carbon))
    }
}
