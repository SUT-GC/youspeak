import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    let hotkeyManager    = HotkeyManager()
    let speechController = SpeechController()
    private let statusBar = StatusBarController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)

        statusBar.setup(controller: speechController)

        hotkeyManager.onKeyDown = { [weak self] in self?.speechController.keyDown() }
        hotkeyManager.onKeyUp   = { [weak self] in self?.speechController.keyUp()   }
        hotkeyManager.start()

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
        w.title                = "YouSpeak 设置"
        w.contentView          = NSHostingView(rootView: SettingsView())
        w.isReleasedWhenClosed = false
        w.center()
        settingsWindow = w

        // Stop hotkey tap while settings is open so key presses land in the
        // settings UI rather than triggering recording.
        hotkeyManager.stop()

        // When the window closes, reload the hotkey — this picks up any
        // configuration changes the user may have made.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object:  w,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hotkeyManager.reload() }
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
