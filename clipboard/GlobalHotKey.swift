import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager {
    var onHotKey: (() -> Void)?

    private static let signature = OSType(0x434C4950)
    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var currentConfiguration: HotKeyConfiguration?

    init(identifier: UInt32 = 1) {
        self.identifier = identifier
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKeyManager.signature,
                      hotKeyID.id == manager.identifier else {
                    return OSStatus(eventNotHandledErr)
                }
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
    func register(_ configuration: HotKeyConfiguration?) -> Bool {
        let previous = currentConfiguration
        unregisterHotKey()

        guard let configuration else {
            currentConfiguration = nil
            return true
        }

        let identifier = EventHotKeyID(signature: Self.signature, id: identifier)
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
