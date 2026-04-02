import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    let hotkeyManager    = HotkeyManager()
    let speechController = SpeechController.shared
    private let statusBar = StatusBarController()
    private var mainWindow:     NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Show in Dock so the app is easy to find.
        NSApp.setActivationPolicy(.regular)

        statusBar.setup(controller: speechController)

        hotkeyManager.onKeyDown = { [weak self] in self?.speechController.keyDown() }
        hotkeyManager.onKeyUp   = { [weak self] in self?.speechController.keyUp()   }
        hotkeyManager.start()

        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(opts)

        // Show the main window on every launch.
        showMain()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Re-show main window when user clicks the Dock icon.
        if !hasVisibleWindows { showMain() }
        return true
    }

    // MARK: - Main window

    private func showMain() {
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: .zero,
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        w.title                = "YouSpeak"
        w.contentView          = NSHostingView(rootView: MainView())
        w.isReleasedWhenClosed = false
        w.center()
        mainWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings window

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

        hotkeyManager.stop()
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
