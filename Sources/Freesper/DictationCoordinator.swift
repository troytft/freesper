import AppKit
import OSLog

@MainActor
final class DictationCoordinator {
  private enum Phase {
    case idle
    case recording
    case transcribing
  }

  private let log: Logger
  private let readiness: AppReadiness
  private let audio: AudioCaptureService
  private let overlay: OverlayController
  private let transcription: TranscriptionService
  private let lastTranscriptStore: LastTranscriptStore
  private var phase: Phase = .idle
  private var transcribeTask: Task<Void, Never>?

  init(
    readiness: AppReadiness,
    audio: AudioCaptureService,
    overlay: OverlayController,
    transcription: TranscriptionService,
    lastTranscriptStore: LastTranscriptStore,
    log: Logger
  ) {
    self.readiness = readiness
    self.audio = audio
    self.overlay = overlay
    self.transcription = transcription
    self.lastTranscriptStore = lastTranscriptStore
    self.log = log
    observeReadiness()
  }

  func start() {
    guard phase == .idle else {
      log.info(
        "[dictation] busy phase=\(String(describing: self.phase), privacy: .public), ignoring start"
      )
      return
    }
    guard readiness.mic == .granted else {
      log.info("[dictation] mic not granted, ignoring start")
      NSSound.beep()
      return
    }
    log.info("[dictation] start")
    phase = .recording
    audio.startIfNeeded()
    audio.beginRecording()
    overlay.setListening()
  }

  func stop() {
    guard phase == .recording else {
      log.info("[dictation] not recording, ignoring stop")
      return
    }
    log.info("[dictation] stop")

    let recording = audio.endRecording()
    audio.stopEngine()
    log.info(
      "[audio] captured samples=\(recording.samples.count, privacy: .public) duration=\(recording.durationSeconds, format: .fixed(precision: 2), privacy: .public)s rmsWindows=\(recording.rmsLevels.count, privacy: .public)"
    )

    phase = .transcribing
    overlay.setTranscribing()
    let samples = recording.samples
    transcribeTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.transcribeAndDeliver(samples: samples)
      // If readiness was lost mid-flight, the abort path already reset
      // phase/overlay. Don't clobber whatever state took over.
      guard !Task.isCancelled else { return }
      self.phase = .idle
      self.overlay.setIdle()
      self.transcribeTask = nil
    }
  }

  private func transcribeAndDeliver(samples: [Float]) async {
    do {
      let text = try await transcription.transcribe(samples: samples)
      guard !Task.isCancelled else { return }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        log.info("[transcribe] empty result, skipping paste")
        return
      }
      log.info("[transcribe] text=\(trimmed, privacy: .public)")
      lastTranscriptStore.text = trimmed

      // Re-check Accessibility right before pasting — the user may have
      // toggled it during the recording. If it's still off, leave the
      // transcript in the clipboard and tell them how to recover.
      readiness.refreshPermissions()
      if readiness.accessibility == .granted {
        await PasteService.paste(trimmed, log: log)
      } else {
        log.info("[transcribe] accessibility missing, copy-only fallback")
        PasteService.copyOnly(trimmed)
        PermissionAlerts.accessibilityAfterTranscript()
      }
    } catch {
      log.error("[transcribe] failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Abort any in-flight session if readiness drops.
  private func observeReadiness() {
    observe { [weak self] in
      _ = self?.readiness.isReady
    } onChange: { [weak self] in
      guard let self, !self.readiness.isReady else { return }
      self.abortActiveSession()
    }
  }

  /// Permission revoked or model lost mid-session: tear down silently. The
  /// setup window will be opened by the menu-bar observer, so no alert here.
  private func abortActiveSession() {
    guard phase != .idle else { return }
    log.info(
      "[dictation] readiness lost during \(String(describing: self.phase), privacy: .public), aborting"
    )
    transcribeTask?.cancel()
    transcribeTask = nil
    if phase == .recording {
      _ = audio.endRecording()
      audio.stopEngine()
    }
    phase = .idle
    overlay.setIdle()
  }
}
