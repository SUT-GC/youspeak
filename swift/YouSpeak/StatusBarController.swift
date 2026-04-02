import AppKit
import Combine

final class StatusBarController {
    private var item: NSStatusItem?
    private var cancellable: AnyCancellable?

    @MainActor func setup(controller: SpeechController) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        update(state: .idle)

        // Build menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(AppDelegate.openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 YouSpeak", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item?.menu = menu

        cancellable = controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(state: state) }
    }

    private func update(state: SpeechController.State) {
        guard let button = item?.button else { return }
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "YouSpeak")
            button.image?.isTemplate = true
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "录音中")
            button.image?.isTemplate = false
            button.image = coloredMicImage(recording: true)
        case .processing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "处理中")
            button.image?.isTemplate = true
        }
    }

    private func coloredMicImage(recording: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) else { return nil }
        let img = NSImage(size: base.size, flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
            base.draw(in: rect)
            return true
        }
        return img
    }
}
