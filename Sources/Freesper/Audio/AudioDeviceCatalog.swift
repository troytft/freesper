import CoreAudio
import Foundation
import OSLog
import Observation

struct AudioInputDevice: Hashable, Identifiable, Sendable {
  enum Transport: Sendable {
    case builtIn
    case usb
    case bluetooth
    case hdmi
    case airPlay
    case virtual
    case aggregate
    case unknown

    var displayLabel: String {
      switch self {
      case .builtIn: return "Built-in"
      case .usb: return "USB"
      case .bluetooth: return "Bluetooth"
      case .hdmi: return "HDMI"
      case .airPlay: return "AirPlay"
      case .virtual: return "Virtual"
      case .aggregate: return "Aggregate"
      case .unknown: return "Other"
      }
    }
  }

  let id: AudioDeviceID
  /// Stable identifier that survives reboots, USB re-plugs, and device
  /// renames. Persist this — never the numeric `id`, which is ephemeral.
  let uid: String
  let name: String
  let transport: Transport
}

/// Lives for the app lifetime — the CoreAudio property listener registered in
/// `init` stays alive until the process exits. There's deliberately no
/// `deinit` cleanup: the catalog never goes out of scope, so removing the
/// listener would just be ceremony.
@MainActor
@Observable
final class AudioDeviceCatalog {
  @ObservationIgnored
  private let log: Logger

  private(set) var devices: [AudioInputDevice] = []

  /// Subscribers notified after `devices` is refreshed. Pulled into its own
  /// Sendable class so the auto-cancelling token can mutate it from any
  /// context without hopping back to the main actor.
  @ObservationIgnored
  private let observerStorage = ObserverStorage()

  init(log: Logger) {
    self.log = log
    refresh()
    installHotPlugListener()
  }

  func deviceID(forUID uid: String) -> AudioDeviceID? {
    devices.first { $0.uid == uid }?.id
  }

  /// The returned token must be retained — drop it to unregister.
  func observeChanges(_ handler: @escaping @MainActor @Sendable () -> Void) -> ObservationToken {
    let id = observerStorage.add(handler)
    let storage = observerStorage
    return ObservationToken { storage.remove(id) }
  }

  final class ObservationToken: Sendable {
    private let cancel: @Sendable () -> Void
    init(_ cancel: @escaping @Sendable () -> Void) { self.cancel = cancel }
    deinit { cancel() }
  }

  private final class ObserverStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [UUID: @MainActor @Sendable () -> Void] = [:]

    func add(_ handler: @escaping @MainActor @Sendable () -> Void) -> UUID {
      lock.withLock {
        let id = UUID()
        observers[id] = handler
        return id
      }
    }

    func remove(_ id: UUID) {
      lock.withLock { _ = observers.removeValue(forKey: id) }
    }

    func snapshot() -> [@MainActor @Sendable () -> Void] {
      lock.withLock { Array(observers.values) }
    }
  }

  // MARK: - Hot-plug

  private func installHotPlugListener() {
    var address = Self.devicesAddress()
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main
    ) { [weak self] _, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refresh()
        for observer in self.observerStorage.snapshot() {
          observer()
        }
      }
    }
    if status != noErr {
      log.error("Failed to install device list listener: \(status, privacy: .public)")
    }
  }

  // MARK: - Enumeration

  nonisolated private static func devicesAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private func refresh() {
    let ids = Self.allAudioDeviceIDs()
    let inputs = ids.compactMap(Self.makeInputDevice(from:))
    devices = inputs
    let names = inputs.map(\.name).joined(separator: ", ")
    log.info("Audio input devices: \(names, privacy: .public)")
  }

  nonisolated private static func allAudioDeviceIDs() -> [AudioDeviceID] {
    var address = devicesAddress()
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size
    )
    guard status == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &ids
    )
    return status == noErr ? ids : []
  }

  nonisolated private static func makeInputDevice(from id: AudioDeviceID) -> AudioInputDevice? {
    // Filter to devices that actually expose input streams — output-only
    // devices (speakers, displays) also appear in the global list.
    guard hasInputStreams(id) else { return nil }
    guard let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID) else {
      return nil
    }
    let name =
      stringProperty(id, selector: kAudioObjectPropertyName)
      ?? stringProperty(id, selector: kAudioDevicePropertyDeviceNameCFString)
      ?? "Unknown device"
    let transport = transportType(id)
    return AudioInputDevice(id: id, uid: uid, name: name, transport: transport)
  }

  nonisolated private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    return status == noErr && size > 0
  }

  nonisolated private static func stringProperty(
    _ id: AudioDeviceID, selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    // CoreAudio returns a +1 retained CFString here — must use
    // Unmanaged and release explicitly via `takeRetainedValue`.
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
    guard status == noErr, let unmanaged = value else { return nil }
    return unmanaged.takeRetainedValue() as String
  }

  nonisolated private static func transportType(_ id: AudioDeviceID) -> AudioInputDevice.Transport {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
    guard status == noErr else { return .unknown }
    switch transport {
    case kAudioDeviceTransportTypeBuiltIn: return .builtIn
    case kAudioDeviceTransportTypeUSB: return .usb
    case kAudioDeviceTransportTypeBluetooth,
      kAudioDeviceTransportTypeBluetoothLE:
      return .bluetooth
    case kAudioDeviceTransportTypeHDMI: return .hdmi
    case kAudioDeviceTransportTypeAirPlay: return .airPlay
    case kAudioDeviceTransportTypeVirtual: return .virtual
    case kAudioDeviceTransportTypeAggregate: return .aggregate
    default: return .unknown
    }
  }
}
