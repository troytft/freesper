import AudioToolbox
import CoreAudio
import OSLog

@MainActor
final class AudioInputUnit {
  struct Format: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
  }

  struct Failure: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? { "\(operation) failed: status=\(status)" }
  }

  typealias AudioHandler =
    @Sendable (_ interleavedSamples: UnsafeBufferPointer<Float>, Format) ->
    Void

  private static let inputElement: AudioUnitElement = 1
  private static let outputElement: AudioUnitElement = 0

  private let log: Logger
  private let relay: CaptureRelay?
  private(set) var deviceID: AudioDeviceID?
  private var format: Format?
  private var isStarted = false
  private var isCapturing = false

  init(log: Logger) {
    self.log = log
    self.relay = Self.makeUnit(log: log).map(CaptureRelay.init(unit:))
    guard let relay else { return }

    var callback = AURenderCallbackStruct(
      inputProc: captureCallback,
      inputProcRefCon: Unmanaged.passUnretained(relay).toOpaque()
    )
    let callbackStatus = AudioUnitSetProperty(
      relay.unit,
      kAudioOutputUnitProperty_SetInputCallback,
      kAudioUnitScope_Global,
      Self.outputElement,
      &callback,
      UInt32(MemoryLayout<AURenderCallbackStruct>.size)
    )
    let listenerStatus = AudioUnitAddPropertyListener(
      relay.unit,
      kAudioUnitProperty_StreamFormat,
      streamFormatListener,
      Unmanaged.passUnretained(self).toOpaque()
    )
    if callbackStatus != noErr || listenerStatus != noErr {
      log.error(
        "Input unit setup failed: callback=\(callbackStatus, privacy: .public) listener=\(listenerStatus, privacy: .public)"
      )
    }
  }

  func setAudioHandler(_ handler: @escaping AudioHandler) {
    relay?.setHandler(handler)
  }

  func prepare(deviceID target: AudioDeviceID) throws {
    let relay = try requireRelay()
    if deviceID != target {
      suspend(relay)
      uninitialize(relay)
      deviceID = nil
      var device = target
      try Self.check(
        AudioUnitSetProperty(
          relay.unit,
          kAudioOutputUnitProperty_CurrentDevice,
          kAudioUnitScope_Global,
          Self.outputElement,
          &device,
          UInt32(MemoryLayout<AudioDeviceID>.size)
        ),
        "Bind input device \(target)"
      )
      deviceID = target
    }
    try synchronizeFormat(relay)
  }

  func start() throws {
    let relay = try requireRelay()
    guard format != nil else { throw Failure(operation: "Start unprepared input unit", status: 0) }
    isStarted = true
    do {
      try resume(relay)
    } catch {
      isStarted = false
      throw error
    }
  }

  func stop() {
    isStarted = false
    guard let relay else { return }
    suspend(relay)
  }

  fileprivate func deviceFormatDidChange() {
    guard let relay, deviceID != nil else { return }
    do {
      try synchronizeFormat(relay)
    } catch {
      log.error(
        "Input format resync failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func synchronizeFormat(_ relay: CaptureRelay) throws {
    let current: Format
    do {
      current = try Self.deviceFormat(of: relay.unit)
    } catch {
      suspend(relay)
      uninitialize(relay)
      throw error
    }
    guard current != format else {
      if isStarted { try resume(relay) }
      return
    }

    suspend(relay)
    uninitialize(relay)
    var client = Self.clientDescription(for: current)
    try Self.check(
      AudioUnitSetProperty(
        relay.unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output,
        Self.inputElement,
        &client,
        UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
      ),
      "Set input client format"
    )
    try Self.check(AudioUnitInitialize(relay.unit), "Initialize input unit")
    relay.configure(current)
    format = current
    log.info(
      "Input unit prepared: device=\(self.deviceID ?? 0, privacy: .public) rate=\(current.sampleRate, privacy: .public) channels=\(current.channelCount, privacy: .public)"
    )
    if isStarted { try resume(relay) }
  }

  private func resume(_ relay: CaptureRelay) throws {
    guard !isCapturing else { return }
    relay.setCapturing(true)
    let status = AudioOutputUnitStart(relay.unit)
    guard status == noErr else {
      relay.setCapturing(false)
      throw Failure(operation: "Start input unit", status: status)
    }
    isCapturing = true
  }

  private func suspend(_ relay: CaptureRelay) {
    guard isCapturing else { return }
    isCapturing = false
    let status = AudioOutputUnitStop(relay.unit)
    if status != noErr {
      log.error("Input unit stop failed: status=\(status, privacy: .public)")
    }
    let losses = relay.finishCapturing()
    if losses.droppedFrames > 0 || losses.failedRenders > 0 {
      log.error(
        "Input unit lost audio: droppedFrames=\(losses.droppedFrames, privacy: .public) failedRenders=\(losses.failedRenders, privacy: .public) lastRenderStatus=\(losses.lastRenderStatus, privacy: .public)"
      )
    }
  }

  private func uninitialize(_ relay: CaptureRelay) {
    guard format != nil else { return }
    format = nil
    let status = AudioUnitUninitialize(relay.unit)
    if status != noErr {
      log.error("Input unit uninitialize failed: status=\(status, privacy: .public)")
    }
  }

  private func requireRelay() throws -> CaptureRelay {
    guard let relay else { throw Failure(operation: "Create input unit", status: 0) }
    return relay
  }

  private static func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw Failure(operation: operation, status: status) }
  }

  private static func deviceFormat(of unit: AudioUnit) throws -> Format {
    var description = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try check(
      AudioUnitGetProperty(
        unit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        inputElement,
        &description,
        &size
      ),
      "Read input device format"
    )
    let format = Format(
      sampleRate: description.mSampleRate, channelCount: Int(description.mChannelsPerFrame))
    guard format.sampleRate > 0, format.channelCount > 0,
      format.channelCount <= CaptureRelay.maxChannelCount
    else {
      throw Failure(
        operation:
          "Use input device format rate=\(format.sampleRate) channels=\(format.channelCount)",
        status: kAudioUnitErr_FormatNotSupported
      )
    }
    return format
  }

  private static func clientDescription(for format: Format) -> AudioStreamBasicDescription {
    let bytesPerFrame = UInt32(format.channelCount * MemoryLayout<Float>.size)
    return AudioStreamBasicDescription(
      mSampleRate: format.sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        | kAudioFormatFlagsNativeEndian,
      mBytesPerPacket: bytesPerFrame,
      mFramesPerPacket: 1,
      mBytesPerFrame: bytesPerFrame,
      mChannelsPerFrame: UInt32(format.channelCount),
      mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
      mReserved: 0
    )
  }

  private static func makeUnit(log: Logger) -> AudioUnit? {
    var description = AudioComponentDescription(
      componentType: kAudioUnitType_Output,
      componentSubType: kAudioUnitSubType_HALOutput,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &description) else {
      log.error("Input unit component not found")
      return nil
    }
    var instance: AudioUnit?
    let status = AudioComponentInstanceNew(component, &instance)
    guard status == noErr, let instance else {
      log.error("Input unit creation failed: status=\(status, privacy: .public)")
      return nil
    }
    var enabled: UInt32 = 1
    var disabled: UInt32 = 0
    let inputStatus = AudioUnitSetProperty(
      instance,
      kAudioOutputUnitProperty_EnableIO,
      kAudioUnitScope_Input,
      inputElement,
      &enabled,
      UInt32(MemoryLayout<UInt32>.size)
    )
    let outputStatus = AudioUnitSetProperty(
      instance,
      kAudioOutputUnitProperty_EnableIO,
      kAudioUnitScope_Output,
      outputElement,
      &disabled,
      UInt32(MemoryLayout<UInt32>.size)
    )
    guard inputStatus == noErr, outputStatus == noErr else {
      log.error(
        "Input unit IO setup failed: input=\(inputStatus, privacy: .public) output=\(outputStatus, privacy: .public)"
      )
      AudioComponentInstanceDispose(instance)
      return nil
    }
    return instance
  }
}

private let streamFormatListener: AudioUnitPropertyListenerProc = {
  refCon, _, _, scope, element in
  guard scope == kAudioUnitScope_Input, element == 1 else { return }
  let owner = Unmanaged<AudioInputUnit>.fromOpaque(refCon).takeUnretainedValue()
  Task { @MainActor in owner.deviceFormatDidChange() }
}

private let captureCallback: AURenderCallback = {
  refCon, actionFlags, timeStamp, busNumber, frameCount, _ in
  Unmanaged<CaptureRelay>.fromOpaque(refCon).takeUnretainedValue()
    .capture(actionFlags, timeStamp, busNumber, frameCount)
  return noErr
}

private final class CaptureRelay: @unchecked Sendable {
  struct Losses {
    var droppedFrames = 0
    var failedRenders = 0
    var lastRenderStatus: OSStatus = noErr
  }

  static let maxChannelCount = 64
  private static let capacity = 1 << 18

  let unit: AudioUnit

  private let captureLock = makeLock()
  private var isCapturing = false
  private var format = AudioInputUnit.Format(sampleRate: 0, channelCount: 1)
  private let staging = makeBuffer()
  private var stagingCount = 0
  private var losses = Losses()

  private let handoffLock = makeLock()
  private var shared = makeBuffer()
  private var sharedCount = 0
  private var sharedFormat = AudioInputUnit.Format(sampleRate: 0, channelCount: 1)

  private let drainQueue = DispatchQueue(label: "audio-input", qos: .userInitiated)
  private let drainSignal: any DispatchSourceUserDataAdd
  private var spare = makeBuffer()
  private var handler: AudioInputUnit.AudioHandler?

  init(unit: AudioUnit) {
    self.unit = unit
    self.drainSignal = DispatchSource.makeUserDataAddSource(queue: drainQueue)
    drainSignal.setEventHandler { [unowned self] in self.drain() }
    drainSignal.activate()
  }

  func setHandler(_ handler: @escaping AudioInputUnit.AudioHandler) {
    drainQueue.sync { self.handler = handler }
  }

  func configure(_ format: AudioInputUnit.Format) {
    os_unfair_lock_lock(captureLock)
    self.format = format
    os_unfair_lock_unlock(captureLock)
  }

  func setCapturing(_ capturing: Bool) {
    os_unfair_lock_lock(captureLock)
    isCapturing = capturing
    os_unfair_lock_unlock(captureLock)
  }

  func finishCapturing() -> Losses {
    os_unfair_lock_lock(captureLock)
    isCapturing = false
    let result = losses
    losses = Losses()
    repeat {
      os_unfair_lock_lock(handoffLock)
      moveStagingToShared()
      os_unfair_lock_unlock(handoffLock)
      drainQueue.sync { drain() }
    } while stagingCount > 0
    os_unfair_lock_unlock(captureLock)
    return result
  }

  func capture(
    _ actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ timeStamp: UnsafePointer<AudioTimeStamp>,
    _ busNumber: UInt32,
    _ frameCount: UInt32
  ) {
    guard os_unfair_lock_trylock(captureLock) else { return }
    defer { os_unfair_lock_unlock(captureLock) }
    guard isCapturing else { return }

    let sampleCount = Int(frameCount) * format.channelCount
    if sampleCount <= Self.capacity - stagingCount {
      var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
          mNumberChannels: UInt32(format.channelCount),
          mDataByteSize: UInt32(sampleCount * MemoryLayout<Float>.size),
          mData: staging + stagingCount
        )
      )
      let status = AudioUnitRender(unit, actionFlags, timeStamp, busNumber, frameCount, &bufferList)
      if status == noErr {
        stagingCount += sampleCount
      } else {
        losses.failedRenders += 1
        losses.lastRenderStatus = status
      }
    } else {
      losses.droppedFrames += Int(frameCount)
    }

    guard stagingCount > 0, os_unfair_lock_trylock(handoffLock) else { return }
    let moved = moveStagingToShared()
    os_unfair_lock_unlock(handoffLock)
    if moved { drainSignal.add(data: 1) }
  }

  @discardableResult
  private func moveStagingToShared() -> Bool {
    let free = Self.capacity - sharedCount
    let count = min(stagingCount, free - free % format.channelCount)
    guard count > 0 else { return false }
    (shared + sharedCount).update(from: staging, count: count)
    sharedCount += count
    sharedFormat = format
    stagingCount -= count
    if stagingCount > 0 {
      staging.update(from: staging + count, count: stagingCount)
    }
    return true
  }

  private func drain() {
    os_unfair_lock_lock(handoffLock)
    swap(&shared, &spare)
    let count = sharedCount
    let format = sharedFormat
    sharedCount = 0
    os_unfair_lock_unlock(handoffLock)
    guard count > 0, let handler else { return }
    handler(UnsafeBufferPointer(start: spare, count: count), format)
  }

  private static func makeLock() -> os_unfair_lock_t {
    let lock = os_unfair_lock_t.allocate(capacity: 1)
    lock.initialize(to: os_unfair_lock())
    return lock
  }

  private static func makeBuffer() -> UnsafeMutablePointer<Float> {
    .allocate(capacity: capacity)
  }
}
