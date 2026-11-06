import Carbon
import KadomoMenuCore

/// System-wide shortcuts through Carbon's `RegisterEventHotKey`, which needs
/// no permission: the launcher's, and any that commands ask for. Fires on the
/// main thread.
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    /// A command's shortcut, with the item's id.
    var onCommand: ((String) -> Void)?
    private var ref: EventHotKeyRef?
    private var commandRefs: [EventHotKeyRef] = []
    /// The items behind `commandRefs`. A press's hot key id is its place here plus `firstCommandID`.
    private var commands: [(id: String, chord: KeyChord)] = []
    private static let signature = OSType(0x4B444D4E) // 'KDMN'
    private static let launcherID: UInt32 = 1
    private static let firstCommandID: UInt32 = 2
    private var handlerInstalled = false
    private(set) var chord: KeyChord?
    private(set) var lastError: String?

    /// Replaces the current shortcut. Returns an error message when macOS refuses it.
    @discardableResult
    func register(_ text: String) -> String? {
        unregister()
        guard let chord = KeyChord.parse(text) else { return fail("\"\(text)\" is not a key chord like \"option+space\"") }
        switch add(chord, id: HotKey.launcherID) {
        case .failure(let reason):
            return fail("Could not register the shortcut: \(reason.message). Pick another `hotkey` in config.toml.")
        case .success(let newRef):
            ref = newRef
            self.chord = chord
            lastError = nil
            Log.info("hotkey registered: \(chord)")
            return nil
        }
    }

    /// Replaces the commands' shortcuts. Returns a message for each that macOS refuses.
    func register(commands wanted: [(id: String, chord: KeyChord)]) -> [String] {
        for ref in commandRefs { UnregisterEventHotKey(ref) }
        commandRefs = []
        commands = []
        var errors: [String] = []
        for command in wanted {
            switch add(command.chord, id: HotKey.firstCommandID + UInt32(commands.count)) {
            case .failure(let reason):
                errors.append("Could not register the shortcut of \(command.id): \(reason.message).")
                Log.error(errors[errors.count - 1])
            case .success(let newRef):
                commandRefs.append(newRef)
                commands.append(command)
            }
        }
        return errors
    }

    private struct Refusal: Error { let message: String }

    private func add(_ chord: KeyChord, id: UInt32) -> Result<EventHotKeyRef, Refusal> {
        guard let code = HotKey.keyCodes[chord.key] else { return .failure(Refusal(message: "the key '\(chord.key)' cannot be used as a global shortcut")) }
        installHandler()
        var mods: UInt32 = 0
        if chord.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if chord.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        if chord.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(code, mods, EventHotKeyID(signature: HotKey.signature, id: id), GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            let reason = status == OSStatus(eventHotKeyExistsErr) ? "another app or command already uses \(chord.symbol)" : "macOS refused \(chord.symbol) (error \(status))"
            return .failure(Refusal(message: reason))
        }
        return .success(newRef)
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
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { HotKey.shared.pressed(pressed.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func pressed(_ id: UInt32) {
        if id == HotKey.launcherID { onPress?(); return }
        let place = Int(id) - Int(HotKey.firstCommandID)
        if commands.indices.contains(place) { onCommand?(commands[place].id) }
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
