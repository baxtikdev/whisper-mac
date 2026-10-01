import Carbon.HIToolbox

final class HotKey {
    var onDown: () -> Void = {}
    var onUp: () -> Void = {}

    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static var nextIdentifier: UInt32 = 1

    init(keyCode: Int, modifiers: Int) throws {
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, specs.count, &specs, context, &handlerRef)
        guard installed == noErr else { throw HotKeyError(status: installed) }

        let id = EventHotKeyID(signature: HotKey.signature, id: identifier)
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            throw HotKeyError(status: registered)
        }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    nonisolated fileprivate static let signature = OSType(0x5748_5350)

    fileprivate func dispatch(id: UInt32, kind: UInt32) -> Bool {
        guard id == identifier else { return false }
        if kind == UInt32(kEventHotKeyPressed) {
            onDown()
        } else if kind == UInt32(kEventHotKeyReleased) {
            onUp()
        }
        return true
    }
}

struct HotKeyError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        status == eventHotKeyExistsErr
            ? "⌥Space is taken by another app (quit other dictation apps)"
            : "Could not register the shortcut (\(status))"
    }
}

private nonisolated func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
    let kind = GetEventKind(event)
    let address = UInt(bitPattern: context)
    let handled = MainActor.assumeIsolated {
        let hotKey = Unmanaged<HotKey>.fromOpaque(UnsafeRawPointer(bitPattern: address)!).takeUnretainedValue()
        return hotKey.dispatch(id: hotKeyID.id, kind: kind)
    }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
