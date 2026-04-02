import ApplicationServices
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.yourname.youspeak", category: "HotkeyManager")

final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    var onKeyDown:      (() -> Void)?
    var onKeyUp:        (() -> Void)?
    /// Called whenever the tap becomes active or inactive.
    var onActiveChange: ((Bool) -> Void)?

    private(set) var isActive = false {
        didSet { if isActive != oldValue { onActiveChange?(isActive) } }
    }

    private var watchedKeyCode:     CGKeyCode    = 61
    private var watchedModifierBit: CGEventFlags = .maskAlternate
    private var isDown = false

    // MARK: - Public

    func start() {
        stop()

        watchedKeyCode     = CGKeyCode(SettingsManager.shared.hotkeyCode)
        watchedModifierBit = modifierBit(for: watchedKeyCode)
        isDown             = false

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

        // tapCreate returns nil when accessibility permission is missing.
        // Don't gate on AXIsProcessTrusted() first — the tap result is authoritative.
        guard let newTap else {
            let trusted = AXIsProcessTrusted()
            log.warning("tapCreate failed (AXIsProcessTrusted=\(trusted, privacy: .public)) — retrying every 2s")
            isActive = false
            scheduleRetry()
            return
        }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        isActive = true
        log.info("Tap active — keyCode \(self.watchedKeyCode, privacy: .public)")
    }

    func stop() {
        retryTimer?.invalidate(); retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil; runLoopSource = nil
        isActive = false
    }

    func reload() { stop(); start() }

    deinit { stop() }

    // MARK: - Retry until accessibility is granted

    private func scheduleRetry() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() {
                log.info("Accessibility granted — starting tap")
                self.retryTimer?.invalidate(); self.retryTimer = nil
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
            if pressed && !isDown  { isDown = true;  log.debug("keyDown  flagsChanged=\(keyCode, privacy: .public)"); onKeyDown?() }
            if !pressed && isDown  { isDown = false; log.debug("keyUp    flagsChanged=\(keyCode, privacy: .public)"); onKeyUp?()   }
            return nil

        case .keyDown where keyCode == watchedKeyCode:
            if !isDown { isDown = true;  log.debug("keyDown  \(keyCode, privacy: .public)"); onKeyDown?() }
            return nil

        case .keyUp where keyCode == watchedKeyCode:
            if isDown  { isDown = false; log.debug("keyUp    \(keyCode, privacy: .public)"); onKeyUp?()   }
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }

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
