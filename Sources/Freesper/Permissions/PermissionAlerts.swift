import AppKit

@MainActor
enum PermissionAlerts {
  static func accessibilityAfterTranscript() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Accessibility required to paste"
    alert.informativeText = """
      Freesper has copied the transcript to your clipboard, but it can't paste \
      without Accessibility access. Press ⌘V to paste manually, or grant access \
      to enable automatic paste next time.

      System Settings → Privacy & Security → Accessibility → enable Freesper.
      """
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")
    if alert.runModal() == .alertFirstButtonReturn {
      SystemSettings.open(.accessibility)
    }
  }
}
