import AppKit
import OSLog

/// Composition root. Builds the dependency graph in `init()`; runtime side
/// effects (notification observers, bootstrap task) happen in `runOnce()`,
/// invoked from the SwiftUI view tree once the environment is available.
@MainActor
final class AppGraph {
  let log = Logger(subsystem: "com.freesper.app", category: "app")
  let readiness: AppReadiness
  let preferences: Preferences
  let deviceCatalog: AudioDeviceCatalog
  let modelManager: ModelManager
  let audio: AudioCaptureService
  let transcription: TranscriptionService
  let overlay: OverlayController
  let dictation: DictationCoordinator
  let hotkey: HotkeyController
  let setupCoordinator: SetupCoordinator

  private var hasStarted = false

  init() {
    let log = self.log
    let readiness = AppReadiness(log: log)
    let preferences = Preferences()
    let deviceCatalog = AudioDeviceCatalog(log: log)
    let modelManager = ModelManager(readiness: readiness, log: log)
    let audio = AudioCaptureService(
      preferences: preferences,
      deviceCatalog: deviceCatalog,
      log: log
    )
    let transcription = TranscriptionService(
      modelDirectory: modelManager.modelDirectory,
      log: log
    )
    let overlay = OverlayController(audio: audio, preferences: preferences, log: log)
    let dictation = DictationCoordinator(
      readiness: readiness,
      audio: audio,
      overlay: overlay,
      transcription: transcription,
      log: log
    )
    let hotkey = HotkeyController(
      preferences: preferences,
      dictation: dictation,
      readiness: readiness,
      log: log
    )
    let setupCoordinator = SetupCoordinator(readiness: readiness, overlay: overlay)

    self.readiness = readiness
    self.preferences = preferences
    self.deviceCatalog = deviceCatalog
    self.modelManager = modelManager
    self.audio = audio
    self.transcription = transcription
    self.overlay = overlay
    self.dictation = dictation
    self.hotkey = hotkey
    self.setupCoordinator = setupCoordinator
  }

  /// Idempotent — SwiftUI may call onAppear more than once per scene flip.
  /// Wires runtime observers and starts the async bootstrap.
  func runOnce() {
    guard !hasStarted else { return }
    hasStarted = true

    audio.observePreferences()

    // Re-check permissions whenever the user comes back to the app —
    // typical moment after they've toggled something in System Settings.
    // The hotkey controller is wired to `readiness.accessibility` directly,
    // so refreshing is enough: any flip to `.granted` brings the tap up.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.readiness.refreshPermissions()
      }
    }

    Task { @MainActor in
      await bootstrap()
      setupCoordinator.start()
    }
  }

  /// Order matters for the hotkey: `AXIsProcessTrustedWithOptions` (called
  /// from `AccessibilityPermission.ensure`) is what registers our PID with
  /// the OS's TCC subsystem. Until it runs, `CGEvent.tapCreate` returns nil
  /// even when the user is already in the trusted list — so permissions must
  /// resolve *before* the controller installs its tap.
  private func bootstrap() async {
    readiness.mic = await MicrophonePermission.request()
    // First-run side effect: registers the app in the Accessibility list
    // so the user has a checkbox to toggle. The non-modal system popup it
    // shows is fine — our menu has the deeplink for the long term.
    AccessibilityPermission.ensure(prompt: true, log: log)
    readiness.accessibility = AccessibilityPermission.check(log: log)
    hotkey.register()
    modelManager.verifyOnLaunch()
  }
}
