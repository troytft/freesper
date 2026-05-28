import AppKit
import OSLog
import SwiftUI

/// Owns the floating pill: panel construction, screen placement, phase-driven
/// resizing, and the timers that drive the live waveform.
///
/// Lifecycle:
///   1. `start()`           — at app launch: pill becomes visible (idle), unless
///                            the overlay is turned off in preferences.
///   2. hover               — controller flips idle ↔ hint and resizes the panel.
///   3. `setListening()`    — keyDown: panel expands, level polling starts.
///   4. `setTranscribing()` — keyUp: levels stop, a progress spinner shows.
///   5. `setIdle()`         — transcript delivered: panel shrinks back to the pill.
@MainActor
final class OverlayController {
  private let log: Logger
  private let audio: AudioCaptureService
  private let preferences: Preferences
  private let model = OverlayState()
  private var panel: OverlayPanel?
  private var pollTask: Task<Void, Never>?
  private var normalizer = WaveformNormalizer()
  private var isRunning = false

  /// The panel is a fixed-size canvas hosting the SwiftUI overlay. Phase
  /// changes resize the *visible capsule* inside SwiftUI; the NSPanel and
  /// its NSHostingView never change size. That stability is what kills the
  /// hover flicker — `NSTrackingArea`s stay bound to fixed rects and AppKit
  /// can't synthesise spurious exit/enter pairs from `animator()`-driven
  /// frame changes (because there are none).
  private static let panelSize = OverlayMetrics.hostSize
  private static let bottomMargin: CGFloat = 12

  init(audio: AudioCaptureService, preferences: Preferences, log: Logger) {
    self.audio = audio
    self.preferences = preferences
    self.log = log
    observeHotkey()
    observeShowOverlay()
  }

  func start() {
    isRunning = true
    syncPanel()
  }

  func stop() {
    isRunning = false
    syncPanel()
  }

  func setListening() {
    model.phase = .listening
    syncWaveform()
  }

  func setTranscribing() {
    stopLevelPolling()
    model.phase = .transcribing
  }

  func setIdle() {
    stopLevelPolling()
    model.phase = .idle
    model.barIntensities = []
  }

  private var shouldShowOverlay: Bool {
    isRunning && preferences.showOverlay
  }

  private func syncPanel() {
    if shouldShowOverlay {
      showPanel()
    } else {
      teardownPanel()
    }
  }

  private func showPanel() {
    ensurePanel()
    guard let panel else { return }
    applyHotkeyLabel()
    place(panel)
    panel.orderFrontRegardless()
    syncWaveform()
    log.info("Overlay shown")
  }

  private func teardownPanel() {
    stopLevelPolling()
    panel?.orderOut(nil)
    panel = nil
    log.info("Overlay hidden")
  }

  private func syncWaveform() {
    guard shouldShowOverlay, model.phase == .listening else {
      stopLevelPolling()
      return
    }
    normalizer.reset()
    refreshWaveform()
    startLevelPolling()
  }

  private func applyHotkeyLabel() {
    model.hotkeyLabel = preferences.hotkeyPreset.label
  }

  private func observeHotkey() {
    observe { [weak self] in
      _ = self?.preferences.hotkeyPreset
    } onChange: { [weak self] in
      self?.applyHotkeyLabel()
    }
  }

  private func observeShowOverlay() {
    observe { [weak self] in
      _ = self?.preferences.showOverlay
    } onChange: { [weak self] in
      self?.syncPanel()
    }
  }

  private func handleEnterIdleZone() {
    if model.phase == .idle {
      model.phase = .hint
    }
  }

  private func handleExitExpandedZone() {
    if model.phase == .hint {
      model.phase = .idle
    }
  }

  private func ensurePanel() {
    if panel != nil { return }
    let p = OverlayPanel(contentSize: Self.panelSize)
    let host = HoverHostingView(rootView: OverlayView(model: model))
    host.model = model
    host.frame = NSRect(origin: .zero, size: Self.panelSize)
    host.autoresizingMask = [.width, .height]
    host.onEnterIdleZone = { [weak self] in self?.handleEnterIdleZone() }
    host.onExitExpandedZone = { [weak self] in self?.handleExitExpandedZone() }
    p.contentView = host
    panel = p
  }

  private func place(_ panel: NSPanel) {
    panel.setFrame(targetFrame(for: Self.panelSize), display: false)
  }

  /// `visibleFrame` already excludes the dock, so a small margin is enough.
  private func targetFrame(for size: NSSize) -> NSRect {
    let screen = preferredScreen()
    let visible = screen.visibleFrame
    let x = visible.midX - size.width / 2
    let y = visible.minY + Self.bottomMargin
    return NSRect(x: x, y: y, width: size.width, height: size.height)
  }

  private func preferredScreen() -> NSScreen {
    let cursor = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(cursor) })
      ?? NSScreen.main
      ?? NSScreen.screens.first!
  }

  private func startLevelPolling() {
    pollTask?.cancel()
    pollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.refreshWaveform()
        try? await Task.sleep(for: .milliseconds(33))
      }
    }
  }

  private func refreshWaveform() {
    let rms = audio.snapshotRecentRMS(count: WaveformView.barCount)
    model.barIntensities = normalizer.intensities(forRecent: rms)
  }

  private func stopLevelPolling() {
    pollTask?.cancel()
    pollTask = nil
  }
}
