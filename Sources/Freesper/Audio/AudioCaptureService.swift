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

  private var engine = AVAudioEngine()
  private var engineDeviceID: AudioDeviceID?
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
  private var shouldBeRunning = false
  private var configChangeObservation: (any NSObjectProtocol)?

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
    self.engineDeviceID = effectiveInputDeviceID()
    observeConfigurationChanges(of: engine)
  }

  deinit {
    if let configChangeObservation {
      NotificationCenter.default.removeObserver(configChangeObservation)
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

  @discardableResult
  func startIfNeeded() -> Bool {
    guard MicrophonePermission.check() == .granted else { return false }
    stateLock.withLock { shouldBeRunning = true }
    guard !engine.isRunning else { return true }
    do {
      try startEngine()
      return true
    } catch {
      log.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  func stopEngine() {
    stateLock.withLock { shouldBeRunning = false }
    if engine.isRunning { engine.stop() }
    // The engine can stop itself on a device change; a leftover tap crashes the next install.
    engine.inputNode.removeTap(onBus: 0)
    stateLock.withLock {
      converter = nil
      rmsLevels.removeAll()
    }
    log.info("Audio engine stopped")
  }

  func startEngine() throws {
    guard !engine.isRunning else { return }

    var formats = prepareInput()
    if !formats.sampleRatesMatch {
      log.error(
        "Input format \(String(describing: formats.output), privacy: .public) doesn't match hardware format \(String(describing: formats.hardware), privacy: .public) and no device change was observed"
      )
      replaceEngine(reason: "stale input format")
      formats = prepareInput()
    }
    // installTap raises an NSException on this mismatch, which Swift can't catch and which can corrupt Swift concurrency state.
    guard formats.sampleRatesMatch else {
      throw NSError(
        domain: "Freesper.Audio",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Input format \(formats.output) doesn't match hardware format \(formats.hardware)"
        ]
      )
    }
    let input = engine.inputNode
    let inputFormat = formats.output
    log.info("Audio input format: \(String(describing: inputFormat), privacy: .public)")

    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
      formats.hardware.channelCount > 0
    else {
      throw NSError(
        domain: "Freesper.Audio",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Input device reports invalid format \(inputFormat), hardware \(formats.hardware)"
        ]
      )
    }

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
    stateLock.withLock { converter = conv }

    // nil format follows the node's live format; a stale snapshot crashes the install.
    input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
      self?.process(inputBuffer: buffer)
    }
    try engine.start()
    log.info("Audio engine started")
  }

  private struct InputFormats {
    let output: AVAudioFormat
    let hardware: AVAudioFormat

    var sampleRatesMatch: Bool { output.sampleRate == hardware.sampleRate }
  }

  private func prepareInput() -> InputFormats {
    let input = engine.inputNode
    input.removeTap(onBus: 0)

    // Bind to the user's chosen input device *before* querying the input
    // format — switching devices changes the format, and `prepare`/`start`
    // both lock the current configuration in.
    applyInputDevice(stateLock.withLock { pendingInputDeviceID }, on: input)

    engine.prepare()
    return InputFormats(output: input.outputFormat(forBus: 0), hardware: input.inputFormat(forBus: 0))
  }

  private func replaceEngine(reason: String) {
    engine = AVAudioEngine()
    // Pays the ~0.5 s input unit setup now rather than on the next hotkey press.
    _ = engine.inputNode
    engineDeviceID = effectiveInputDeviceID()
    observeConfigurationChanges(of: engine)
    log.info("Audio engine replaced: \(reason, privacy: .public)")
  }

  private func effectiveInputDeviceID() -> AudioDeviceID? {
    stateLock.withLock { pendingInputDeviceID } ?? AudioDeviceCatalog.defaultInputDeviceID()
  }

  private func observeConfigurationChanges(of engine: AVAudioEngine) {
    if let configChangeObservation {
      NotificationCenter.default.removeObserver(configChangeObservation)
    }
    configChangeObservation = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self, engineID = ObjectIdentifier(engine)] _ in
      Task { @MainActor [weak self] in
        guard let self, ObjectIdentifier(self.engine) == engineID else { return }
        self.handleConfigurationChange()
      }
    }
  }

  @MainActor
  private static func resolveDeviceID(uid: String?, catalog: AudioDeviceCatalog) -> AudioDeviceID? {
    guard let uid else { return nil }
    return catalog.deviceID(forUID: uid)
  }

  private func applyInputDevice(_ deviceID: AudioDeviceID?, on inputNode: AVAudioInputNode) {
    guard let deviceID, let unit = inputNode.audioUnit else { return }
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
    }
  }

  @MainActor
  private func reconfigureForCurrentSelection() {
    let target = Self.resolveDeviceID(uid: preferences.microphoneUID, catalog: deviceCatalog)
    if preferences.microphoneUID != nil && target == nil {
      log.info("Selected mic is not connected, falling back to system default")
    }
    let isRecording = stateLock.withLock {
      pendingInputDeviceID = target
      return shouldBeRunning
    }
    guard effectiveInputDeviceID() != engineDeviceID else { return }
    if isRecording {
      haltEngine()
      replaceEngine(reason: "input device changed during recording")
      startIfNeeded()
    } else {
      replaceEngine(reason: "input device changed")
    }
  }

  @MainActor
  private func handleConfigurationChange() {
    guard stateLock.withLock({ shouldBeRunning }) else { return }
    log.info("Audio engine configuration changed → restarting engine")
    haltEngine()
    startIfNeeded()
  }

  @MainActor
  private func haltEngine() {
    let input = engine.inputNode
    if engine.isRunning { engine.stop() }
    input.removeTap(onBus: 0)
    stateLock.withLock { converter = nil }
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

  private func converterCompatible(with format: AVAudioFormat) -> AVAudioConverter? {
    stateLock.withLock {
      if let converter, converter.inputFormat == format { return converter }
      converter = AVAudioConverter(from: format, to: targetFormat)
      return converter
    }
  }

  private func process(inputBuffer: AVAudioPCMBuffer) {
    guard let converter = converterCompatible(with: inputBuffer.format) else { return }

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
