import FluidAudio
import Foundation
import OSLog

/// Backed by FluidAudio's downloader: it owns URL/checksum/file-layout details
/// for Parakeet, so this class doesn't need a manual SHA-256 + URL pair.
@MainActor
final class ModelManager {
  private let log: Logger
  private let readiness: AppReadiness
  private var task: Task<Void, Never>?

  /// Parakeet TDT 0.6B v3 — the same model the app has always used. If this
  /// changes, the on-disk folder name changes too (it's the HF repo's basename),
  /// so any old payload is naturally bypassed by `modelsExist(at:)` returning false.
  private static let asrVersion: AsrModelVersion = .v3

  init(readiness: AppReadiness, log: Logger) {
    self.readiness = readiness
    self.log = log
  }

  /// `<appsupp>/Freesper/Models/parakeet-tdt-0.6b-v3-coreml/`. We pass this as
  /// FluidAudio's `targetDir`; FluidAudio strips the last component and writes
  /// files under `<appsupp>/Freesper/Models/<repo.folderName>/`, which lands
  /// at the same location.
  ///
  /// `nil` if the application support directory is unreachable (sandbox
  /// failure, hard-broken filesystem); callers surface that as a model-state
  /// failure instead of crashing.
  var modelDirectory: URL? {
    do {
      let base = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      // FluidAudio's `Repo.folderName` is internal; the safe public path is the
      // last component of its default cache dir (`parakeet-tdt-0.6b-v3-coreml`).
      let folderName = AsrModels.defaultCacheDirectory(for: Self.asrVersion).lastPathComponent
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
    guard let directory = modelDirectory else {
      readiness.model = .failed(ModelError.applicationSupportUnavailable)
      return
    }
    if AsrModels.modelsExist(at: directory, version: Self.asrVersion) {
      log.info("[model] verified on launch at \(directory.path, privacy: .public)")
      readiness.model = .ready
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
    guard let directory = modelDirectory else {
      readiness.model = .failed(ModelError.applicationSupportUnavailable)
      return
    }
    readiness.model = .downloading(progress: 0)
    let version = Self.asrVersion
    let log = self.log
    task = Task.detached { [weak self] in
      // ProgressHandler is called on an unspecified queue; bounce through
      // the main actor before touching `readiness`.
      let progressHandler: DownloadUtils.ProgressHandler = { [weak self] snapshot in
        Task { await self?.publishProgress(snapshot.fractionCompleted) }
      }
      do {
        _ = try await AsrModels.download(
          to: directory,
          version: version,
          progressHandler: progressHandler
        )
        try Task.checkCancellation()
        await self?.finishSuccess()
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

  private func finishSuccess() {
    log.info("[model] download complete")
    task = nil
    readiness.model = .ready
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
