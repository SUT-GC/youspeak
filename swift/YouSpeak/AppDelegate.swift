import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    let hotkeyManager    = HotkeyManager()
    @MainActor lazy var speechController = SpeechController()
    private let statusBar = StatusBarController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // No Dock icon
        NSApp.setActivationPolicy(.accessory)

        // Status bar
        statusBar.setup(controller: speechController)

        // Hotkey
        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in self?.speechController.keyDown() }
        }
        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in self?.speechController.keyUp() }
        }
        hotkeyManager.start()

        // Ask for accessibility if needed
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(opts)
    }

    @objc func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "YouSpeak 设置"
        w.contentView = NSHostingView(rootView: SettingsView())
        w.center()
        w.isReleasedWhenClosed = false
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
