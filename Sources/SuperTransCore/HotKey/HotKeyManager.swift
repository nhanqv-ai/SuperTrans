import Carbon
import AppKit

public protocol HotKeyManaging: AnyObject {
    var onTranslateTrigger: (() -> Void)? { get set }
    var onHistoryTrigger: (() -> Void)? { get set }
    func registerTranslateHotKey(keyCode: UInt32, modifiers: UInt32)
    func registerHistoryHotKey(keyCode: UInt32, modifiers: UInt32)
    func unregisterAll()
}

public final class HotKeyManager: HotKeyManaging, @unchecked Sendable {
    public static let shared = HotKeyManager()

    public var onTranslateTrigger: (() -> Void)?
    public var onHistoryTrigger: (() -> Void)?

    private var translateHotKeyRef: EventHotKeyRef?
    private var historyHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = 0x5354524E // 'STRN'
    private static let translateHotKeyID: UInt32 = 1
    private static let historyHotKeyID: UInt32 = 2

    public init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else { return noErr }
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return noErr }

                if hkID.id == HotKeyManager.translateHotKeyID {
                    mgr.onTranslateTrigger?()
                } else if hkID.id == HotKeyManager.historyHotKeyID {
                    mgr.onHistoryTrigger?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
    }

    public func registerTranslateHotKey(
        keyCode: UInt32 = AppSettings.defaultTranslateHotKeyKeyCode,
        modifiers: UInt32 = AppSettings.defaultTranslateHotKeyModifiers
    ) {
        if let ref = translateHotKeyRef {
            UnregisterEventHotKey(ref)
            translateHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.translateHotKeyID)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &translateHotKeyRef
        )
    }

    public func registerHistoryHotKey(
        keyCode: UInt32 = AppSettings.defaultHistoryHotKeyKeyCode,
        modifiers: UInt32 = AppSettings.defaultHistoryHotKeyModifiers
    ) {
        if let ref = historyHotKeyRef {
            UnregisterEventHotKey(ref)
            historyHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.historyHotKeyID)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &historyHotKeyRef
        )
    }

    public func unregisterAll() {
        if let ref = translateHotKeyRef {
            UnregisterEventHotKey(ref)
            translateHotKeyRef = nil
        }
        if let ref = historyHotKeyRef {
            UnregisterEventHotKey(ref)
            historyHotKeyRef = nil
        }
    }

    deinit {
        unregisterAll()
        if let hRef = handlerRef {
            RemoveEventHandler(hRef)
        }
    }

    // MARK: - Formatting Helpers

    public static func formatShortcut(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { parts.append("Ctrl") }
        if (modifiers & UInt32(optionKey)) != 0 { parts.append("Option") }
        if (modifiers & UInt32(shiftKey)) != 0 { parts.append("Shift") }
        if (modifiers & UInt32(cmdKey)) != 0 { parts.append("Cmd") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }

    public static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        default: return "Key(\(keyCode))"
        }
    }
}
