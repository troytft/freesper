import AppKit

enum SystemSettingsPane: String {
  case microphone = "Privacy_Microphone"
  case accessibility = "Privacy_Accessibility"
}

@MainActor
enum SystemSettings {
  static func open(_ pane: SystemSettingsPane) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}
