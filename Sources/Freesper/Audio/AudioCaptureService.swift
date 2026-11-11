@preconcurrency import AVFoundation
import CoreAudio
import OSLog

/// Capture runs only while a dictation session is active, so the OS mic
/// indicator only lights up while the user is actually recording.
///
/// `@unchecked Sendable` because captured audio arrives on the input unit's
/// delivery queue, not on any actor. Capture lifecycle is isolated to the
/// main actor; state shared with the delivery queue is guarded by `stateLock`.
final class AudioCaptureService: @unchecked Sendable {
  struct Recording {
    let samples: [Float]
    let rmsLevels: [Float]

    var durationSeconds: Double {
      Double(samples.count) / 16_000.0
    }
  }

  private struct NoInputDevice: LocalizedError {
    var errorDescription: String? { "No input device available" }
  }

  private let log: Logger
  private let preferences: Preferences
  private let deviceCatalog: AudioDeviceCatalog
  private let inputUnit: AudioInputUnit
  private var deviceObservation: AudioDeviceCatalog.ObservationToken?

  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
  )!

  private let stateLock = NSLock()
  private var converter: AVAudioConverter?
  /// nil → not recording. Non-nil → samples accumulated this session.
  private var recording: [Float]?
  private var rmsLevels: [Float] = []
  private var rmsWindowSum: Float = 0
  private var rmsWindowFill = 0

  /// ~30 ms windows at 16 kHz produce ~33 RMS values per second — fine for
  /// driving the overlay waveform.
  private let rmsWindow = 512

  @MainActor
  init(
    preferences: Preferences,
    deviceCatalog: AudioDeviceCatalog,
    inputUnit: AudioInputUnit,
    log: Logger
  ) {
    self.preferences = preferences
    self.deviceCatalog = deviceCatalog
    self.inputUnit = inputUnit
    self.log = log
    self.deviceObservation = deviceCatalog.observeChanges { [weak self] in
      self?.prepareForCurrentSelection()
    }
    inputUnit.setAudioHandler { [weak self] samples, format in
      self?.process(samples, format: format)
    }
    prepareForCurrentSelection()
  }

  /// Kept out of `init` so the composition root controls when observation
  /// begins.
  @MainActor
  func observePreferences() {
    observe { [weak self] in
      _ = self?.preferences.microphoneUID
    } onChange: { [weak self] in
      self?.prepareForCurrentSelection()
    }
  }

  @MainActor
  @discardableResult
  func start() -> Bool {
    guard MicrophonePermission.check() == .granted else { return false }
    do {
      guard let deviceID = effectiveInputDeviceID() else { throw NoInputDevice() }
      try inputUnit.prepare(deviceID: deviceID)
      try inputUnit.start()
      log.info("Audio capture started")
      return true
    } catch {
      log.error("Audio capture start failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  @MainActor
  func stop() {
    inputUnit.stop()
    stateLock.withLock { converter = nil }
    log.info("Audio capture stopped")
  }

  @MainActor
  private func effectiveInputDeviceID() -> AudioDeviceID? {
    if let uid = preferences.microphoneUID, let selected = deviceCatalog.deviceID(forUID: uid) {
      return selected
    }
    return AudioDeviceCatalog.defaultInputDeviceID()
  }

  @MainActor
  private func prepareForCurrentSelection() {
    guard MicrophonePermission.check() == .granted else { return }
    guard let target = effectiveInputDeviceID() else { return }
    if target != inputUnit.deviceID, let uid = preferences.microphoneUID,
      deviceCatalog.deviceID(forUID: uid) == nil
    {
      log.info("Selected mic is not connected, falling back to system default")
    }
    do {
      try inputUnit.prepare(deviceID: target)
    } catch {
      log.error("Input device switch failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func beginRecording() {
    stateLock.withLock {
      recording = []
      rmsLevels.removeAll()
      rmsWindowSum = 0
      rmsWindowFill = 0
    }
  }

  func endRecording() -> Recording {
    stateLock.withLock {
      let result = Recording(samples: recording ?? [], rmsLevels: rmsLevels)
      recording = nil
      rmsLevels.removeAll()
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

  private func converter(forSampleRate sampleRate: Double) -> AVAudioConverter? {
    stateLock.withLock {
      if let converter, converter.inputFormat.sampleRate == sampleRate { return converter }
      converter = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      ).flatMap { AVAudioConverter(from: $0, to: targetFormat) }
      return converter
    }
  }

  private func process(_ samples: UnsafeBufferPointer<Float>, format: AudioInputUnit.Format) {
    let inputFrames = samples.count / format.channelCount
    guard inputFrames > 0 else { return }
    guard let converter = converter(forSampleRate: format.sampleRate),
      let inputBuffer = AVAudioPCMBuffer(
        pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(inputFrames)),
      let inputData = inputBuffer.floatChannelData?[0]
    else {
      log.error(
        "Cannot convert input at \(format.sampleRate, privacy: .public) Hz to \(self.targetFormat, privacy: .public)"
      )
      return
    }
    for frame in 0..<inputFrames {
      inputData[frame] = samples[frame * format.channelCount]
    }
    inputBuffer.frameLength = AVAudioFrameCount(inputFrames)

    let ratio = targetFormat.sampleRate / format.sampleRate
    let outCapacity = AVAudioFrameCount(Double(inputFrames) * ratio + 1_024)
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
    let converted = UnsafeBufferPointer(start: channelData, count: frames)

    stateLock.withLock {
      guard recording != nil else { return }
      recording?.append(contentsOf: converted)
      for sample in converted {
        rmsWindowSum += sample * sample
        rmsWindowFill += 1
        if rmsWindowFill == rmsWindow {
          rmsLevels.append(sqrt(rmsWindowSum / Float(rmsWindow)))
          rmsWindowSum = 0
          rmsWindowFill = 0
        }
      }
    }
  }
}
