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
            button.image           = NSImage(systemSymbolName: "mic",
                                             accessibilityDescription: "YouSpeak")
            button.image?.isTemplate = true

        case .recording:
            button.image = recordingIcon()

        case .processing:
            button.image           = NSImage(systemSymbolName: "ellipsis.circle",
                                             accessibilityDescription: "处理中")
            button.image?.isTemplate = true
        }
    }

    /// A mic.fill icon with a small red dot — drawn correctly (dot on top of mic).
    private func recordingIcon() -> NSImage? {
        let size: NSSize = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            // 1. Draw mic first as a template (respects dark/light mode).
            if let sf = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
                sf.isTemplate = true
                sf.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            // 2. Red dot on top to signal recording.
            let dot = rect.insetBy(dx: rect.width * 0.55, dy: rect.height * 0.55)
                          .offsetBy(dx: rect.width * 0.22, dy: -rect.height * 0.22)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }
}
