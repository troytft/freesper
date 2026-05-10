@preconcurrency import AVFoundation

enum MicrophonePermission {
  static func check() -> PermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return .granted
    case .denied, .restricted: return .denied
    case .notDetermined: return .notDetermined
    @unknown default: return .denied
    }
  }

  static func request() async -> PermissionStatus {
    let current = check()
    guard current == .notDetermined else { return current }
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    return granted ? .granted : .denied
  }
}
