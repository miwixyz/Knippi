// App/Sources/Capture/ScrollCaptureEscapeHotKey.swift
import Carbon.HIToolbox
import Foundation

/// Esc as a system-wide hot key while a scrolling capture is on screen.
///
/// The capture overlay never becomes key (the scrolled app keeps focus), so a
/// local key monitor misses Esc, and the key event tap only works with
/// Accessibility permission. A Carbon hot key needs no permission.
@MainActor
final class ScrollCaptureEscapeHotKey {
    private static let signature: OSType = 0x4B_6E_45_73 // "KnEs"
    private static var nextID: UInt32 = 1
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private var hotKey: EventHotKeyRef?

    /// Registers Esc; `action` runs on the main actor for every press.
    /// Returns nil if the system refused the hot key.
    init?(action: @escaping () -> Void) {
        guard Self.installHandlerIfNeeded() else { return nil }
        id = Self.nextID
        Self.nextID &+= 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape), 0,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        hotKey = ref
        Self.actions[id] = action
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        Self.actions[id] = nil
    }

    static var registeredCount: Int { actions.count }

    /// Runs the action for a hot key press of ours; false for anyone else's.
    static func handlePress(signature: OSType, id: UInt32) -> Bool {
        guard signature == Self.signature, let action = actions[id] else { return false }
        action()
        return true
    }

    private static func installHandlerIfNeeded() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let read = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            // Other hot keys (the app's shortcuts) are passed on untouched.
            guard read == noErr, hotKeyID.signature == ScrollCaptureEscapeHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let handled = MainActor.assumeIsolated {
                ScrollCaptureEscapeHotKey.handlePress(signature: hotKeyID.signature, id: hotKeyID.id)
            }
            return handled ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &spec, nil, &handler)
        return status == noErr
    }
}
