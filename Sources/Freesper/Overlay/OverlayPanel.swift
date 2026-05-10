import AppKit

/// - `.nonactivatingPanel` keeps the foreground app focused so push-to-talk
///   doesn't steal focus mid-keystroke in Slack/etc.
/// - Mouse events ARE accepted: the pill needs hover to expand into the hint.
/// - `.canJoinAllSpaces + .fullScreenAuxiliary` so it's visible the same in
///   fullscreen Xcode/Safari/etc.
/// - `hasShadow = false`: the panel is fixed at the expanded size (240×40)
///   so that the hover tracking areas stay stable. With `hasShadow = true`
///   on a fully transparent borderless panel, macOS draws the shadow on the
///   panel rect — not on the alpha mask of the SwiftUI content — which made
///   the idle pill look like a giant dark bar. The expanded pill reads fine
///   without a window shadow thanks to its blurred fill and outline.
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(contentSize: NSSize) {
    super.init(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    isFloatingPanel = true
    level = .floating
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    isMovableByWindowBackground = false
    animationBehavior = .none
    collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle,
      .stationary,
    ]
    alphaValue = 1
  }
}
