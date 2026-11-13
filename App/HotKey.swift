import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, stored as a virtual key code plus modifier flags.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, limited to ⌃⌥⇧⌘.
    var modifiers: UInt
    /// Display name of the key, e.g. "Space" or "I".
    var key: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_Space),
                                    modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
                                    key: "Space")

    /// Builds a shortcut from a key press; requires at least one of ⌃⌥⌘ so plain typing can't be bound.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.isDisjoint(with: [.control, .option, .command]) else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = flags.rawValue
        key = Self.keyName(for: event)
    }

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    var display: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + key
    }

    fileprivate var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_F1...kVK_F20 where event.specialKey != nil: "F\(fKeyNumber(event.keyCode))"
        default: event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }

    private static func fKeyNumber(_ keyCode: UInt16) -> Int {
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return (fKeys.firstIndex(of: Int(keyCode)) ?? 0) + 1
    }
}

/// Registers the global shortcut with the Carbon hot key API, which works in the sandbox
/// and needs no Accessibility permission.
@MainActor @Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private(set) var shortcut: Shortcut
    /// False when another app already owns the shortcut.
    private(set) var isRegistered = false
    @ObservationIgnored var onPress: () -> Void = {}

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    private static let defaultsKey = "shortcut"

    private init() {
        shortcut = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
    }

    func set(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: Self.defaultsKey)
        register()
    }

    func register() {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4950_4341), id: 1) // 'IPCA'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.onPress() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
