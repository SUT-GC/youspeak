import CoreGraphics
import Foundation

final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: (() -> Void)?
    var onKeyUp:   (() -> Void)?

    private var watchedKeyCode:     CGKeyCode    = 61
    private var watchedModifierBit: CGEventFlags = .maskAlternate
    private var isDown = false

    func start() {
        let code           = CGKeyCode(SettingsManager.shared.hotkeyCode)
        watchedKeyCode     = code
        watchedModifierBit = modifierBit(for: code)
        isDown             = false

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
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return mgr.handle(type: type, event: event)
            },
            userInfo: ptr
        )
        guard let tap else {
            print("[HotkeyManager] tapCreate failed — grant Accessibility permission")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Stop and restart with current SettingsManager values (picks up hotkey changes).
    func reload() { stop(); start() }

    deinit { stop() }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged where keyCode == watchedKeyCode:
            // Check the specific modifier bit for this key rather than comparing
            // raw values, which is fragile when multiple modifiers are held.
            let pressed = event.flags.contains(watchedModifierBit)
            if pressed && !isDown {
                isDown = true
                onKeyDown?()
            } else if !pressed && isDown {
                isDown = false
                onKeyUp?()
            }
            return nil  // swallow

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

    // MARK: - Helpers

    private func modifierBit(for keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 57:     return .maskAlphaShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63:     return .maskSecondaryFn
        default:     return []
        }
    }
}
