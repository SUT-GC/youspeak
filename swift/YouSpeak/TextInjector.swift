import CoreGraphics
import Foundation

final class TextInjector {
    func type(_ text: String) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for char in text {
            let s = String(char)
            postChar(s, source: src, down: true)
            postChar(s, source: src, down: false)
            Thread.sleep(forTimeInterval: 0.004)
        }
    }

    private func postChar(_ char: String, source: CGEventSource, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return }
        var uni = Array(char.utf16)
        event.keyboardSetUnicodeString(stringLength: uni.count, unicodeString: &uni)
        event.post(tap: .cgSessionEventTap)
    }
}
