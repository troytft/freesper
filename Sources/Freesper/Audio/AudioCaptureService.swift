@preconcurrency import AVFoundation
import CoreAudio
import OSLog

/// The engine is started on demand when a dictation session begins and torn
/// down again as soon as it ends — so the OS mic indicator only lights up
/// while the user is actually recording.
///
/// `@unchecked Sendable` because the input tap callback runs on the audio
/// render thread, not on any actor. Mutable state is guarded by `stateLock`.
final class AudioCaptureService: @unchecked Sendable {
  struct Recording {
    let samples: [Float]
    let rmsLevels: [Float]

    var durationSeconds: Double {
      Double(samples.count) / 16_000.0
    }
  }

  private let log: Logger
  private let preferences: Preferences
  private let deviceCatalog: AudioDeviceCatalog
  private var deviceObservation: AudioDeviceCatalog.ObservationToken?

  private let engine = AVAudioEngine()
  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
  )!
  private var converter: AVAudioConverter?

  private let stateLock = NSLock()
  /// nil → not recording. Non-nil → samples accumulated this session.
  private var recording: [Float]?
  private var rmsLevels: [Float] = []
  /// Effective AudioDeviceID we want bound to the engine's input unit, or
  /// `nil` to follow the system default. Resolved on the main actor whenever
  /// preferences or the device list change; read by `startEngine` from
  /// whatever thread happens to be starting the engine.
  private var pendingInputDeviceID: AudioDeviceID?
  /// Mirrors what's actually wired into the input unit. Guarded by
  /// `stateLock` because `startEngine` may run off the main actor.
  private var currentInputDeviceID: AudioDeviceID?

  /// ~30 ms windows at 16 kHz produce ~33 RMS values per second — fine for
  /// driving the overlay waveform and cheap enough to do every callback.
  private let rmsWindow = 512

  @MainActor
  init(preferences: Preferences, deviceCatalog: AudioDeviceCatalog, log: Logger) {
    self.preferences = preferences
    self.deviceCatalog = deviceCatalog
    self.log = log
    // Seed the resolved device id so the first `startEngine` call binds
    // to the right hardware without waiting for an observation tick.
    self.pendingInputDeviceID = Self.resolveDeviceID(
      uid: preferences.microphoneUID, catalog: deviceCatalog)
    self.deviceObservation = deviceCatalog.observeChanges { [weak self] in
      self?.reconfigureForCurrentSelection()
    }
  }

  /// Kept out of `init` so the composition root controls when observation
  /// begins.
  @MainActor
  func observePreferences() {
    observe { [weak self] in
      _ = self?.preferences.microphoneUID
    } onChange: { [weak self] in
      self?.reconfigureForCurrentSelection()
    }
  }

  func startIfNeeded() {
    guard MicrophonePermission.check() == .granted else { return }
    guard !engine.isRunning else { return }
    do {
      try startEngine()
    } catch {
      log.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func stopEngine() {
    guard engine.isRunning else { return }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    converter = nil
    stateLock.withLock {
      rmsLevels.removeAll()
      currentInputDeviceID = nil
    }
    log.info("Audio engine stopped")
  }

  func startEngine() throws {
    guard !engine.isRunning else { return }

    let input = engine.inputNode

    // Bind to the user's chosen input device *before* querying the input
    // format — switching devices changes the format, and `prepare`/`start`
    // both lock the current configuration in.
    let target = stateLock.withLock { pendingInputDeviceID }
    let bound = applyInputDevice(target, on: input)
    stateLock.withLock { currentInputDeviceID = bound }

    engine.prepare()
    let inputFormat = input.outputFormat(forBus: 0)
    log.info("Audio input format: \(String(describing: inputFormat), privacy: .public)")

    guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
      throw NSError(
        domain: "Freesper.Audio",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Cannot create converter from \(inputFormat) to \(targetFormat)"
        ]
      )
    }
    converter = conv

    input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
      self?.process(inputBuffer: buffer)
    }
    try engine.start()
    log.info("Audio engine started")
  }

  @MainActor
  private static func resolveDeviceID(uid: String?, catalog: AudioDeviceCatalog) -> AudioDeviceID? {
    guard let uid else { return nil }
    return catalog.deviceID(forUID: uid)
  }

  private func applyInputDevice(_ deviceID: AudioDeviceID?, on inputNode: AVAudioInputNode)
    -> AudioDeviceID?
  {
    guard let deviceID, let unit = inputNode.audioUnit else { return nil }
    var id = deviceID
    let status = AudioUnitSetProperty(
      unit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &id,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    if status != noErr {
      log.error(
        "Failed to bind input device \(deviceID, privacy: .public): status=\(status, privacy: .public)"
      )
      return nil
    }
    return deviceID
  }

  @MainActor
  private func reconfigureForCurrentSelection() {
    let target = Self.resolveDeviceID(uid: preferences.microphoneUID, catalog: deviceCatalog)
    if preferences.microphoneUID != nil && target == nil {
      log.info("Selected mic is not connected, falling back to system default")
    }
    let needsRebuild: Bool = stateLock.withLock {
      pendingInputDeviceID = target
      return target != currentInputDeviceID
    }
    guard needsRebuild else { return }
    // While the engine is idle (no active session), there's nothing to
    // rebuild — the next `startEngine()` will pick up `pendingInputDeviceID`.
    guard engine.isRunning else { return }
    log.info("Mic selection changed → rebuilding engine")
    rebuildEngine()
  }

  @MainActor
  private func rebuildEngine() {
    let input = engine.inputNode
    if engine.isRunning { engine.stop() }
    input.removeTap(onBus: 0)
    converter = nil
    // Drop any buffered audio so the next recording doesn't carry samples
    // captured at the previous device's format.
    stateLock.withLock {
      recording = nil
      rmsLevels.removeAll()
    }
    startIfNeeded()
  }

  func beginRecording() {
    stateLock.withLock {
      recording = []
      rmsLevels.removeAll()
    }
  }

  func endRecording() -> Recording {
    stateLock.withLock {
      let result = Recording(samples: recording ?? [], rmsLevels: rmsLevels)
      recording = nil
      return result
    }
  }

  /// Pads with zeros at the start so the overlay always renders exactly
  /// `count` bars without bookkeeping in the view layer.
  func snapshotRecentRMS(count: Int) -> [Float] {
    guard count > 0 else { return [] }
    return stateLock.withLock {
      if rmsLevels.count >= count {
        return Array(rmsLevels.suffix(count))
      }
      return Array(repeating: 0, count: count - rmsLevels.count) + rmsLevels
    }
  }

  /// Reference wrapper for the converter input block. Boxes the one-shot
  /// "fed yet?" flag and the input buffer so the `@Sendable` closure has
  /// nothing mutable captured by reference.
  private final class ConvertInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var fed = false
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
  }

  private func process(inputBuffer: AVAudioPCMBuffer) {
    guard let converter else { return }

    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 1_024)
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity)
    else {
      return
    }

    let state = ConvertInput(buffer: inputBuffer)
    var error: NSError?
    let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
      if state.fed {
        outStatus.pointee = .noDataNow
        return nil
      }
      state.fed = true
      outStatus.pointee = .haveData
      return state.buffer
    }

    if status == .error || error != nil {
      log.error("Convert error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
      return
    }

    let frames = Int(outBuffer.frameLength)
    guard frames > 0, let channelData = outBuffer.floatChannelData?[0] else { return }
    let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))

    // Slice the converted buffer into ~30 ms windows so the overlay sees
    // multiple RMS samples per audio callback rather than one chunky one.
    var windowRMS: [Float] = []
    windowRMS.reserveCapacity(frames / rmsWindow + 1)
    var idx = 0
    while idx < frames {
      let end = min(idx + rmsWindow, frames)
      var sumSq: Float = 0
      for j in idx..<end { sumSq += samples[j] * samples[j] }
      let n = Float(end - idx)
      windowRMS.append(sqrt(sumSq / n))
      idx = end
    }

    stateLock.withLock {
      if recording != nil {
        recording?.append(contentsOf: samples)
        rmsLevels.append(contentsOf: windowRMS)
      }
    }
  }
}
