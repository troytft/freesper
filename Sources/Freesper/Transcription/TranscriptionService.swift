import FluidAudio
import Foundation
import OSLog

actor TranscriptionService {
  private let log: Logger
  private let modelDirectory: URL?
  private var manager: AsrManager?

  /// `modelDirectory` is owned and prepared by `ModelManager`; we only load
  /// from it. `nil` means the application support folder was unreachable —
  /// in practice the dictation pipeline is gated off via `AppReadiness.isReady`
  /// in that case, so `transcribe(...)` should never actually be called.
  init(modelDirectory: URL?, log: Logger) {
    self.modelDirectory = modelDirectory
    self.log = log
  }

  private func ensureLoaded() async throws -> AsrManager {
    if let manager { return manager }
    guard let modelDirectory else {
      throw ModelError.applicationSupportUnavailable
    }
    log.info("Loading Parakeet TDT v3 models from \(modelDirectory.path, privacy: .public)…")
    let models = try await AsrModels.load(from: modelDirectory, version: .v3)
    let manager = AsrManager()
    try await manager.loadModels(models)
    self.manager = manager
    log.info("ASR models loaded")
    return manager
  }

  func transcribe(samples: [Float]) async throws -> String {
    let manager = try await ensureLoaded()
    var state = try TdtDecoderState()
    let result = try await manager.transcribe(samples, decoderState: &state)
    return result.text
  }
}
