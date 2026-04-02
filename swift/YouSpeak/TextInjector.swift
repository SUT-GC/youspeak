import CoreGraphics
import Foundation

final class TextInjector {

    /// Types `text` at the current cursor position character by character.
    /// Async so it yields the main actor between characters instead of blocking it.
    @MainActor
    func type(_ text: String) async {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for char in text {
            let s = String(char)
            postChar(s, source: src, down: true)
            postChar(s, source: src, down: false)
            // 4 ms gap — yield the main actor rather than blocking the thread.
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
    }

    private func postChar(_ char: String, source: CGEventSource, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return }
        var uni = Array(char.utf16)
        event.keyboardSetUnicodeString(stringLength: uni.count, unicodeString: &uni)
        event.post(tap: .cgSessionEventTap)
    }
}
