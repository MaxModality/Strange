import Carbon
import Foundation
import StrangeCore

public enum HotKeyError: Error, Equatable {
    case handlerInstallation(Int32)
    case registration(shortcut: String, code: Int32)
}

/// Uses OS hotkey registration, rather than observing the user's keyboard input.
/// Stops explicitly on shutdown and releases registrations on the main actor.
@MainActor public final class GlobalHotKeys {
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private let onPress: @MainActor (WindowCommand) -> Void
    private static let signature: OSType = 0x53545247 // STRG

    public init(onPress: @escaping @MainActor (WindowCommand) -> Void) {
        self.onPress = onPress
    }

    isolated deinit {
        for reference in registrations { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Registration is all-or-nothing. Collisions are reported, never stolen.
    public func start() throws {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard Thread.isMainThread, let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == GlobalHotKeys.signature,
                      identifier.id > 0, identifier.id <= UInt32(HotKeyBinding.defaults.count) else {
                    return OSStatus(eventNotHandledErr)
                }
                owner.onPress(HotKeyBinding.defaults[Int(identifier.id - 1)].command)
                return noErr
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            stop()
            throw HotKeyError.handlerInstallation(status)
        }

        do {
            for (index, binding) in HotKeyBinding.defaults.enumerated() {
                var reference: EventHotKeyRef?
                let identifier = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
                let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, identifier,
                                                 GetApplicationEventTarget(), 0, &reference)
                guard status == noErr, let reference else {
                    throw HotKeyError.registration(shortcut: binding.label, code: status)
                }
                registrations.append(reference)
            }
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        for reference in registrations { UnregisterEventHotKey(reference) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
