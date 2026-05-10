import ApplicationServices
import OSLog

enum AccessibilityPermission {
  /// Trigger the system prompt if needed. macOS adds the app to
  /// System Settings → Privacy & Security → Accessibility on the first
  /// `prompt: true` call, even if the user dismisses the dialog. Subsequent
  /// `prompt: true` calls don't re-show the prompt.
  @discardableResult
  static func ensure(prompt: Bool, log: Logger) -> Bool {
    // kAXTrustedCheckOptionPrompt resolves to "AXTrustedCheckOptionPrompt".
    // Using the literal sidesteps Swift 6 Sendable checks on the CFString global.
    let opts: CFDictionary = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(opts)
    log.info("Accessibility trusted=\(trusted, privacy: .public)")
    return trusted
  }

  static func check(log: Logger) -> PermissionStatus {
    ensure(prompt: false, log: log) ? .granted : .denied
  }
}
