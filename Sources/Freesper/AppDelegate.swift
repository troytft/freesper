import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var onReopen: (() -> Void)?

  nonisolated func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows: Bool
  ) -> Bool {
    if hasVisibleWindows { return true }
    MainActor.assumeIsolated {
      onReopen?()
    }
    return false
  }
}
