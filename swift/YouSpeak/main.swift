import AppKit

// main.swift always executes on the main thread. Tell Swift's type-checker
// the same thing via assumeIsolated so we can construct @MainActor types here.
let app = NSApplication.shared
// Set policy before run() so the Dock icon and menu bar appear immediately.
app.setActivationPolicy(.regular)

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
