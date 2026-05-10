import AppKit
import OSLog

/// Toggle-mode bookkeeping (one press starts, the next stops) lives here —
/// the monitor itself doesn't know about hold vs toggle.
@MainActor
final class HotkeyController {
  private let log: Logger
  private let preferences: Preferences
  private let dictation: DictationCoordinator
  private let readiness: AppReadiness
  private let monitor: HotkeyMonitor

  /// True while a toggle-mode session is "armed". Reset whenever the binding
  /// changes so a stale toggle doesn't survive a rebind.
  private var toggledOn = false

  init(
    preferences: Preferences,
    dictation: DictationCoordinator,
    readiness: AppReadiness,
    log: Logger
  ) {
    self.preferences = preferences
    self.dictation = dictation
    self.readiness = readiness
    self.log = log
    self.monitor = HotkeyMonitor(log: log)
  }

  /// `CGEvent.tapCreate` returns nil for a process the OS hasn't yet linked
  /// to its TCC entry, which on first launch happens *after* the
  /// `AXIsProcessTrustedWithOptions` call in bootstrap — so the tap is only
  /// installed once accessibility is granted. The accessibility observer
  /// below picks it back up the moment readiness flips.
  func register() {
    monitor.onDown = { [weak self] in self?.handleDown() }
    monitor.onUp = { [weak self] in self?.handleUp() }
    applyPreset()
    startTapIfAllowed()
    observePreferences()
    observeAccessibility()
  }

  /// Idempotent: `monitor.start()` short-circuits when the tap is already
  /// installed. We gate on accessibility because `tapCreate` will silently
  /// fail (return nil) without it, leaving us in a state that looks
  /// installed-but-broken to anyone reading `monitor.isRunning`.
  private func startTapIfAllowed() {
    guard readiness.accessibility == .granted else {
      log.info("[hotkey] tap start skipped — accessibility not granted")
      return
    }
    let started = monitor.start()
    log.info(
      "[hotkey] tap start preset=\(self.preferences.hotkeyPreset.rawValue, privacy: .public) running=\(started, privacy: .public)"
    )
  }

  // MARK: - Triggers

  private func handleDown() {
    switch preferences.hotkeyMode {
    case .hold:
      dictation.start()
    case .toggle:
      if toggledOn {
        toggledOn = false
        dictation.stop()
      } else {
        toggledOn = true
        dictation.start()
      }
    }
  }

  private func handleUp() {
    guard preferences.hotkeyMode == .hold else { return }
    dictation.stop()
  }

  // MARK: - Observation

  private func observePreferences() {
    observe { [weak self] in
      _ = self?.preferences.hotkeyPreset
      _ = self?.preferences.hotkeyMode
    } onChange: { [weak self] in
      self?.applyPreset()
    }
  }

  /// Bring the tap up the moment accessibility flips to granted — covers the
  /// first-launch flow where the user toggles the permission in System
  /// Settings after the bootstrap retry has already run.
  private func observeAccessibility() {
    observe { [weak self] in
      _ = self?.readiness.accessibility
    } onChange: { [weak self] in
      self?.startTapIfAllowed()
    }
  }

  private func applyPreset() {
    // Stop any in-flight toggle session before swapping bindings —
    // otherwise the new hotkey could "inherit" a recording the user
    // started under the old one.
    if toggledOn {
      toggledOn = false
      dictation.stop()
    }
    monitor.update(hotkey: preferences.hotkeyPreset.hotkey)
    log.info(
      "[hotkey] rebind preset=\(self.preferences.hotkeyPreset.rawValue, privacy: .public) mode=\(self.preferences.hotkeyMode.rawValue, privacy: .public)"
    )
  }
}
