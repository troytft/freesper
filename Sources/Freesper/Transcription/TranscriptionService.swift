import FluidAudio
import Foundation
import OSLog

actor TranscriptionService {
  private let log: Logger
  private let modelDirectory: URL?
  private var manager: AsrManager?
  private var loadTask: Task<AsrManager, Error>?

  /// `modelDirectory` is owned and prepared by `ModelManager`; we only load
  /// from it. `nil` means the application support folder was unreachable —
  /// in practice the dictation pipeline is gated off via `AppReadiness.isReady`
  /// in that case, so `transcribe(...)` should never actually be called.
  init(modelDirectory: URL?, log: Logger) {
    self.modelDirectory = modelDirectory
    self.log = log
  }

  func prewarm() async {
    _ = try? await ensureLoaded()
  }

  private func ensureLoaded() async throws -> AsrManager {
    if let manager { return manager }
    if let loadTask { return try await loadTask.value }
    guard let modelDirectory else {
      throw ModelError.applicationSupportUnavailable
    }
    let log = self.log
    let task = Task {
      log.info("Loading Parakeet TDT v3 models from \(modelDirectory.path, privacy: .public)…")
      let models = try await AsrModels.load(from: modelDirectory, version: .v3)
      let manager = AsrManager()
      try await manager.loadModels(models)
      log.info("ASR models loaded")
      return manager
    }
    loadTask = task
    do {
      let manager = try await task.value
      self.manager = manager
      self.loadTask = nil
      return manager
    } catch {
      self.loadTask = nil
      throw error
    }
  }

  func transcribe(samples: [Float]) async throws -> String {
    let manager = try await ensureLoaded()
    var state = try TdtDecoderState()
    let result = try await manager.transcribe(samples, decoderState: &state)
    return result.text
  }
}
