import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    let hotkeyManager    = HotkeyManager()
    let speechController = SpeechController.shared
    private let statusBar = StatusBarController()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        setupMainMenu()
        statusBar.setup(controller: speechController)

        hotkeyManager.onKeyDown = { [weak self] in self?.speechController.keyDown() }
        hotkeyManager.onKeyUp   = { [weak self] in self?.speechController.keyUp()   }
        hotkeyManager.start()

        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(opts)

        showMain()
    }

    // MARK: - Main menu
    // macOS dispatches ⌘V/⌘C/⌘X by scanning the main menu for matching
    // key equivalents. Without an Edit menu these shortcuts never reach
    // text fields, so paste appears broken even though the field works fine.
    private func setupMainMenu() {
        let bar = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 YouSpeak",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 YouSpeak",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Edit menu — this is what makes ⌘V / ⌘C / ⌘X work in text fields
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")),            keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")),            keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = bar
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

    // MARK: - Settings

    @objc func openSettings() {
        NotificationCenter.default.post(name: .showSettingsTab, object: nil)
        showMain()
    }
}

