import CoreGraphics
import Foundation

final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: (() -> Void)?
    var onKeyUp:   (() -> Void)?

    private var watchedKeyCode: CGKeyCode = 61
    private var prevFlags: CGEventFlags = []
    private var isDown = false

    func start() {
        watchedKeyCode = CGKeyCode(SettingsManager.shared.hotkeyCode)
        prevFlags      = []
        isDown         = false

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
                              | (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)

        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return mgr.handle(type: type, event: event)
            },
            userInfo: ptr
        )
        guard let tap else {
            print("[HotkeyManager] tapCreate failed — grant Accessibility permission in System Settings")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil; runLoopSource = nil
    }

    func reload() { stop(); start() }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged where keyCode == watchedKeyCode:
            // modifier key: detect press/release by flag delta
            let flags = event.flags
            let nowDown = flags.rawValue > prevFlags.rawValue
            prevFlags = flags
            if nowDown && !isDown {
                isDown = true
                onKeyDown?()
            } else if !nowDown && isDown {
                isDown = false
                onKeyUp?()
            }
            return nil    // swallow event

        case .keyDown where keyCode == watchedKeyCode:
            if !isDown { isDown = true; onKeyDown?() }
            return nil

        case .keyUp where keyCode == watchedKeyCode:
            if isDown { isDown = false; onKeyUp?() }
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }
}
