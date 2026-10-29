import FluidAudio
import Foundation
import OSLog

/// Backed by FluidAudio's downloader: it owns URL/checksum/file-layout details
/// for Parakeet, so this class doesn't need a manual SHA-256 + URL pair.
@MainActor
final class ModelManager {
  private let log: Logger
  private let readiness: AppReadiness
  private let prewarm: () async -> Void
  private var task: Task<Void, Never>?
  private var prepareTask: Task<Void, Never>?

  /// Changing this changes the on-disk folder (the HF repo's basename): the new
  /// model is downloaded and `removeUnusedModels` deletes the previous folder.
  static let asrVersion: AsrModelVersion = .ultra

  init(readiness: AppReadiness, prewarm: @escaping () async -> Void, log: Logger) {
    self.readiness = readiness
    self.prewarm = prewarm
    self.log = log
  }

  /// `<appsupp>/Freesper/Models/parakeet-ultra-coreml/`. We pass this as
  /// FluidAudio's `targetDir`; FluidAudio strips the last component and writes
  /// files under `<appsupp>/Freesper/Models/<repo.folderName>/`, which lands
  /// at the same location.
  ///
  /// `nil` if the application support directory is unreachable (sandbox
  /// failure, hard-broken filesystem); callers surface that as a model-state
  /// failure instead of crashing.
  static func resolveModelDirectory(log: Logger) -> URL? {
    do {
      let base = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      // FluidAudio's `Repo.folderName` is internal; the safe public path is the
      // last component of its default cache dir (`parakeet-ultra-coreml`).
      let folderName = AsrModels.defaultCacheDirectory(for: asrVersion).lastPathComponent
      return
        base
        .appendingPathComponent("Freesper", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent(folderName, isDirectory: true)
    } catch {
      log.error(
        "[model] application support unreachable: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  func verifyOnLaunch() {
    guard let directory = Self.resolveModelDirectory(log: log) else {
      readiness.model = .failed(ModelError.applicationSupportUnavailable)
      return
    }
    if AsrModels.modelsExist(at: directory, version: Self.asrVersion) {
      log.info("[model] verified on launch at \(directory.path, privacy: .public)")
      removeUnusedModels(keeping: directory)
      prepareThenReady()
      return
    }
    log.info("[model] not present, will download")
    readiness.model = .notDownloaded
    startDownload()
  }

  func retry() {
    guard case .failed = readiness.model else { return }
    startDownload()
  }

  private func startDownload() {
    if task != nil { return }
    guard let directory = Self.resolveModelDirectory(log: log) else {
      readiness.model = .failed(ModelError.applicationSupportUnavailable)
      return
    }
    readiness.model = .downloading(progress: 0)
    let version = Self.asrVersion
    let log = self.log
    task = Task.detached { [weak self] in
      // ProgressHandler is called on an unspecified queue; bounce through
      // the main actor before touching `readiness`.
      let progressHandler: ProgressHandler = { [weak self] snapshot in
        Task { await self?.publishProgress(snapshot.fractionCompleted) }
      }
      do {
        _ = try await AsrModels.download(
          to: directory,
          version: version,
          progressHandler: progressHandler
        )
        try Task.checkCancellation()
        await self?.finishSuccess(directory: directory)
      } catch is CancellationError {
        await self?.finishCancelled()
      } catch {
        // `error` may not be Sendable, so rephrase as a Sendable string for
        // the log and a Sendable wrapper for the readiness payload.
        let message = error.localizedDescription
        log.error("[model] download failed: \(message, privacy: .public)")
        await self?.finishFailed(ModelError.downloadFailed(message))
      }
    }
  }

  private func publishProgress(_ fraction: Double) {
    guard case .downloading = readiness.model else { return }
    readiness.model = .downloading(progress: fraction)
  }

  private func finishSuccess(directory: URL) {
    log.info("[model] download complete")
    task = nil
    removeUnusedModels(keeping: directory)
    prepareThenReady()
  }

  /// Everything else under `Models/` is deleted, so only re-downloadable
  /// models may live there.
  private func removeUnusedModels(keeping directory: URL) {
    let log = self.log
    Task.detached {
      let fileManager = FileManager.default
      let modelsRoot = directory.deletingLastPathComponent()
      let entries: [URL]
      do {
        entries = try fileManager.contentsOfDirectory(
          at: modelsRoot,
          includingPropertiesForKeys: nil
        )
      } catch {
        log.error(
          "[model] couldn't list models folder: \(error.localizedDescription, privacy: .public)"
        )
        return
      }
      for entry in entries where entry.lastPathComponent != directory.lastPathComponent {
        do {
          try fileManager.removeItem(at: entry)
          log.info("[model] removed unused \(entry.lastPathComponent, privacy: .public)")
        } catch {
          log.error(
            "[model] couldn't remove \(entry.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
  }

  /// Eagerly compile the models (`.preparing`) before `.ready` so the first
  /// transcription doesn't pay the ~20 s CoreML compilation cost. Prewarm
  /// failure is non-fatal: the files exist, so we still go `.ready` and let the
  /// first `transcribe` reload lazily.
  private func prepareThenReady() {
    readiness.model = .preparing
    prepareTask = Task { @MainActor [weak self] in
      await self?.prewarm()
      guard let self, !Task.isCancelled else { return }
      self.readiness.model = .ready
      self.prepareTask = nil
    }
  }

  private func finishCancelled() {
    log.info("[model] download cancelled")
    task = nil
    readiness.model = .notDownloaded
  }

  private func finishFailed(_ error: Error) {
    task = nil
    readiness.model = .failed(error)
  }
}

enum ModelError: LocalizedError {
  case applicationSupportUnavailable
  case downloadFailed(String)

  var errorDescription: String? {
    switch self {
    case .applicationSupportUnavailable:
      return "Couldn't access the Application Support folder. Check disk permissions."
    case .downloadFailed(let message):
      return message
    }
  }
}
