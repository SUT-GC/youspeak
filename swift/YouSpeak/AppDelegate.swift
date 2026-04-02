import AppKit
import SwiftUI

@main
@MainActor  // All NSApplicationDelegate callbacks run on main; make it explicit.
final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    let hotkeyManager    = HotkeyManager()
    let speechController = SpeechController()
    private let statusBar = StatusBarController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // No Dock icon
        NSApp.setActivationPolicy(.accessory)

        statusBar.setup(controller: speechController)

        hotkeyManager.onKeyDown = { [weak self] in
            self?.speechController.keyDown()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            self?.speechController.keyUp()
        }
        hotkeyManager.start()

        // Prompt for Accessibility permission on first launch.
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
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        w.title = "YouSpeak 设置"
        w.contentView = NSHostingView(rootView: SettingsView())
        w.center()
        w.isReleasedWhenClosed = false
        settingsWindow = w

        // Pause hotkey while settings window is open so key capture doesn't trigger recording.
        hotkeyManager.stop()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object:  w,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hotkeyManager.start() }
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
