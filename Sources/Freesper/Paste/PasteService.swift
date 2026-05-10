import AppKit
import OSLog

/// Clipboard rather than the Accessibility API because Electron, Web, and
/// terminal apps don't expose their text fields via `AXUIElement`. The 300 ms
/// restore delay lets the foreground app finish reading the pasteboard before
/// the original contents come back.
@MainActor
enum PasteService {
  private static let restoreDelay: Duration = .milliseconds(300)
  private static let keyV: CGKeyCode = 0x09

  static func paste(_ text: String, log: Logger) async {
    let pb = NSPasteboard.general
    let snapshot = capture(pb)

    pb.clearContents()
    pb.setString(text, forType: .string)

    sendCmdV(log: log)

    try? await Task.sleep(for: restoreDelay)

    restore(snapshot, into: pb)
  }

  /// Fallback used when Accessibility is missing. Writes the transcript to
  /// the pasteboard without sending ⌘V and without restoring — the user
  /// pastes manually, so the new contents must stay there.
  static func copyOnly(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
  }

  private static func capture(_ pb: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
    guard let types = pb.types else { return [] }
    return types.compactMap { type in
      pb.data(forType: type).map { (type, $0) }
    }
  }

  private static func restore(
    _ items: [(NSPasteboard.PasteboardType, Data)],
    into pb: NSPasteboard
  ) {
    pb.clearContents()
    for (type, data) in items {
      pb.setData(data, forType: type)
    }
  }

  private static func sendCmdV(log: Logger) {
    let src = CGEventSource(stateID: .combinedSessionState)
    guard
      let down = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true),
      let up = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
    else {
      log.error("Failed to create ⌘V CGEvent")
      return
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }
}
