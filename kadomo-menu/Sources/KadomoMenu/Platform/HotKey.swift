import Carbon
import KadomoMenuCore

/// A system-wide shortcut through Carbon's `RegisterEventHotKey`, which needs
/// no permission. Fires on the main thread.
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private(set) var chord: KeyChord?
    private(set) var lastError: String?

    /// Replaces the current shortcut. Returns an error message when macOS refuses it.
    @discardableResult
    func register(_ text: String) -> String? {
        unregister()
        guard let chord = KeyChord.parse(text) else { return fail("\"\(text)\" is not a key chord like \"option+space\"") }
        guard let code = HotKey.keyCodes[chord.key] else { return fail("the key '\(chord.key)' cannot be used as a global shortcut") }
        installHandler()
        var mods: UInt32 = 0
        if chord.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if chord.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        if chord.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: OSType(0x4B444D4E), id: 1) // 'KDMN'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            let reason = status == OSStatus(eventHotKeyExistsErr) ? "another app already uses \(chord.symbol)" : "macOS refused \(chord.symbol) (error \(status))"
            return fail("Could not register the shortcut: \(reason). Pick another `hotkey` in config.toml.")
        }
        ref = newRef
        self.chord = chord
        lastError = nil
        Log.info("hotkey registered: \(chord)")
        return nil
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        chord = nil
    }

    private func fail(_ message: String) -> String {
        lastError = message
        Log.error(message)
        return message
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { HotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// ANSI virtual key codes.
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "space": 49, "enter": 36, "tab": 48, "escape": 53, "backspace": 51, "delete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111,
    ]
}
