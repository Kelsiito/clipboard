import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var currentConfiguration: HotKeyConfiguration?

    init() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onHotKey?()
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &handlerRef
        )
    }

    @discardableResult
    func register(_ configuration: HotKeyConfiguration) -> Bool {
        let previous = currentConfiguration
        unregisterHotKey()

        var identifier = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        guard status == noErr else {
            if let previous { _ = register(previous) }
            return false
        }
        hotKeyRef = newRef
        currentConfiguration = configuration
        return true
    }

    func stop() {
        unregisterHotKey()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit { stop() }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
