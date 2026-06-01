import Carbon.HIToolbox
@preconcurrency import CoreGraphics
import Foundation
import OSLog

/// Threading: the tap callback runs on whatever run loop the source is added
/// to. We attach to `CFRunLoopGetMain()`, so callbacks land on the main thread
/// and we can stay `@MainActor` end-to-end without locks. The matcher and
/// state mutation happen synchronously inside the callback — the only thing
/// the callback emits is the user's `onDown`/`onUp` closures, which run on
/// main as well.
@MainActor
final class HotkeyMonitor {
  private let log: Logger

  /// Fired exactly once per genuine press; auto-repeats are suppressed.
  var onDown: (() -> Void)?
  /// Fired exactly once per genuine release.
  var onUp: (() -> Void)?

  private var hotkey: Hotkey?
  private var isPressed = false

  private var tap: CFMachPort?

  init(log: Logger) {
    self.log = log
  }

  // MARK: - Lifecycle

  /// Returns false if accessibility isn't granted (the OS returns a nil port).
  @discardableResult
  func start() -> Bool {
    guard tap == nil else { return true }

    let mask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    let refcon = Unmanaged.passUnretained(self).toOpaque()
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: HotkeyMonitor.tapCallback,
        userInfo: refcon
      )
    else {
      log.error("[hotkey] CGEvent.tapCreate failed — accessibility likely not granted")
      return false
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)

    self.tap = port
    log.info("[hotkey] tap installed")
    return true
  }

  /// Resets pressed-state so we don't leak a phantom "still pressed" between
  /// bindings.
  func update(hotkey: Hotkey) {
    self.hotkey = hotkey
    self.isPressed = false
  }

  // MARK: - Callback dispatch

  private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    // We attach the run loop source to the main run loop, so callbacks
    // arrive on the main thread. Asserting isolation lets us call into
    // @MainActor state without hopping.
    return MainActor.assumeIsolated {
      let swallow = monitor.handle(type: type, event: event)
      return swallow ? nil : Unmanaged.passUnretained(event)
    }
  }

  private func handle(type: CGEventType, event: CGEvent) -> Bool {
    // Tap can be disabled by the system if a callback takes too long or
    // if user input "trips" it. Re-enable so we don't silently die.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap {
        log.warning("[hotkey] tap disabled (\(type.rawValue, privacy: .public)), re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return false
    }

    guard let hotkey else { return false }
    let flags = event.flags.intersection(Hotkey.relevantMask)

    switch type {
    case .flagsChanged:
      guard hotkey.isBareModifier else { return false }
      if let target = hotkey.modifierKeyCode {
        let changedKey = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard changedKey == target else { return false }
      }
      let nowPressed = flags.contains(hotkey.modifiers)
      if nowPressed && !isPressed {
        isPressed = true
        log.info("[hotkey] down (bare modifier)")
        emitDown()
      } else if !nowPressed && isPressed {
        isPressed = false
        log.info("[hotkey] up (bare modifier)")
        emitUp()
      }
      return false

    case .keyDown:
      guard !hotkey.isBareModifier,
        let target = hotkey.keyCode,
        CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == target,
        flags == hotkey.modifiers
      else { return false }
      if !isPressed {
        isPressed = true
        log.info("[hotkey] down")
        emitDown()
      }
      return true

    case .keyUp:
      guard !hotkey.isBareModifier,
        let target = hotkey.keyCode,
        CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == target,
        isPressed
      else { return false }
      // Don't gate keyUp on flag matching: if the user releases the
      // main key while still holding a modifier, we still want to fire
      // the up edge. The "are we currently pressed" guard is enough.
      isPressed = false
      log.info("[hotkey] up")
      emitUp()
      return true

    default:
      return false
    }
  }

  private func emitDown() {
    Task { @MainActor [weak self] in self?.onDown?() }
  }

  private func emitUp() {
    Task { @MainActor [weak self] in self?.onUp?() }
  }
}
