import AppKit
import Combine

final class StatusBarController {
    private var item: NSStatusItem?
    private var cancellable: AnyCancellable?

    @MainActor func setup(controller: SpeechController) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        update(state: .idle)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置…",
                                action: #selector(AppDelegate.openSettings),
                                keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 YouSpeak",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item?.menu = menu

        cancellable = controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(state: state) }
    }

    @MainActor private func update(state: SpeechController.State) {
        guard let button = item?.button else { return }
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "YouSpeak")
            button.image?.isTemplate = true
        case .recording:
            button.image = redMicImage()
        case .processing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "处理中")
            button.image?.isTemplate = true
        }
    }

    private func redMicImage() -> NSImage? {
        guard let sf = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "录音中") else { return nil }
        let size = NSSize(width: 18, height: 18)
        let img  = NSImage(size: size, flipped: false) { rect in
            sf.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6)).fill()
            return true
        }
        return img
    }
}
