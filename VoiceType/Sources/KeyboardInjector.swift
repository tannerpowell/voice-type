import Carbon
import Foundation

enum KeyboardInjector {
    /// Type a string into the currently focused text field using CGEvents.
    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            let char = UniChar(scalar.value)
            var chars = [char]

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
