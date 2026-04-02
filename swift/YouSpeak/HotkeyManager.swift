import ApplicationServices
import CoreGraphics
import Foundation

final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    var onKeyDown: (() -> Void)?
    var onKeyUp:   (() -> Void)?

    private var watchedKeyCode:     CGKeyCode    = 61
    private var watchedModifierBit: CGEventFlags = .maskAlternate
    private var isDown = false

    // MARK: - Public

    func start() {
        stop()  // clean up any previous tap first

        watchedKeyCode     = CGKeyCode(SettingsManager.shared.hotkeyCode)
        watchedModifierBit = modifierBit(for: watchedKeyCode)
        isDown             = false

        guard AXIsProcessTrusted() else {
            print("[HotkeyManager] ⚠️  No Accessibility permission — will retry every 2s")
            scheduleRetry()
            return
        }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
                              | (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)

        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let newTap = CGEvent.tapCreate(
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
        guard let newTap else {
            print("[HotkeyManager] ❌ tapCreate failed (returned nil) — will retry")
            scheduleRetry()
            return
        }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        print("[HotkeyManager] ✅ tap active — watching keyCode \(watchedKeyCode)")
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    func reload() { stop(); start() }

    deinit { stop() }

    // MARK: - Retry

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() {
                print("[HotkeyManager] 🔓 Accessibility granted — starting tap")
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.start()
            }
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged where keyCode == watchedKeyCode:
            let pressed = event.flags.contains(watchedModifierBit)
            if pressed && !isDown {
                isDown = true
                print("[HotkeyManager] keyDown (flagsChanged) code=\(keyCode)")
                onKeyDown?()
            } else if !pressed && isDown {
                isDown = false
                print("[HotkeyManager] keyUp (flagsChanged) code=\(keyCode)")
                onKeyUp?()
            }
            return nil  // swallow

        case .keyDown where keyCode == watchedKeyCode:
            if !isDown {
                isDown = true
                print("[HotkeyManager] keyDown code=\(keyCode)")
                onKeyDown?()
            }
            return nil

        case .keyUp where keyCode == watchedKeyCode:
            if isDown {
                isDown = false
                print("[HotkeyManager] keyUp code=\(keyCode)")
                onKeyUp?()
            }
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Modifier bit map

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
