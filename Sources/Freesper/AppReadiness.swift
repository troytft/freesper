import AppKit
import OSLog
import SwiftUI

@MainActor
@Observable
final class AppReadiness {
  @ObservationIgnored
  private let log: Logger

  var mic: PermissionStatus = .notDetermined
  var accessibility: PermissionStatus = .notDetermined
  var model: ModelState = .notDownloaded

  init(log: Logger) {
    self.log = log
  }

  var isReady: Bool {
    mic == .granted && accessibility == .granted && model.isReady
  }

  var iconName: String {
    isReady ? "mic" : "exclamationmark.triangle"
  }

  func refreshPermissions() {
    mic = MicrophonePermission.check()
    accessibility = AccessibilityPermission.check(log: log)
  }
}
