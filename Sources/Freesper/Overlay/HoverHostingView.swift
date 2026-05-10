import AppKit
import SwiftUI

/// `NSHostingView` subclass with two fixed `NSTrackingArea`s implementing a
/// hysteresis hover model:
///
/// - **Idle zone** (smaller, sized like the visible thin pill): entering it
///   from outside means the user is aiming at the pill — fire `onEnterIdleZone`
///   so the controller expands.
/// - **Expanded zone** (larger, sized like the expanded pill): leaving it
///   means the cursor has truly left the visible expanded shape — fire
///   `onExitExpandedZone` so the controller collapses.
///
/// Both areas are added once in `updateTrackingAreas` and never removed or
/// recreated. The host view itself is fixed at `OverlayMetrics.hostSize` —
/// the SwiftUI capsule inside grows/shrinks, but the NSView never resizes.
/// Combined, this kills the flicker: AppKit no longer synthesises spurious
/// exit/enter pairs from `animator()`-driven frame changes (because there
/// are none), and tracking-area transitions only fire when the cursor
/// *actually* crosses one of two fixed rects in screen space.
final class HoverHostingView: NSHostingView<OverlayView> {
  var onEnterIdleZone: (() -> Void)?
  var onExitExpandedZone: (() -> Void)?
  /// Set immediately after `init(rootView:)` so `hitTest` can read the
  /// current phase. Without this, the host view would absorb every
  /// click in the visually-empty area around the idle pill.
  var model: OverlayState?

  private var idleArea: NSTrackingArea?
  private var expandedArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if idleArea == nil {
      let rect = Self.centeredRect(of: OverlayMetrics.idleHoverZone, in: bounds.size)
      let area = NSTrackingArea(
        rect: rect,
        options: [.mouseEnteredAndExited, .activeAlways],
        owner: self,
        userInfo: ["zone": "idle"]
      )
      addTrackingArea(area)
      idleArea = area
    }

    if expandedArea == nil {
      let area = NSTrackingArea(
        rect: bounds,
        options: [.mouseEnteredAndExited, .activeAlways],
        owner: self,
        userInfo: ["zone": "expanded"]
      )
      addTrackingArea(area)
      expandedArea = area
    }
  }

  /// Make the panel "transparent" outside the visible capsule. AppKit
  /// resolves clicks against this rect; points outside it return nil and
  /// the click is delivered to whatever window sits behind the panel.
  /// Tracking-area events (`mouseEntered`/`mouseExited`) fire on geometric
  /// rect crossings independent of `hitTest`, so hover-to-expand still
  /// works even when most of the host view is hit-test-transparent.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let phase = model?.phase ?? .idle
    let activeRect: NSRect =
      (phase == .idle)
      ? Self.centeredRect(of: OverlayMetrics.idleHitTestSize, in: bounds.size)
      : bounds
    guard activeRect.contains(point) else { return nil }
    return super.hitTest(point)
  }

  override func mouseEntered(with event: NSEvent) {
    guard zone(for: event) == "idle" else { return }
    onEnterIdleZone?()
  }

  override func mouseExited(with event: NSEvent) {
    guard zone(for: event) == "expanded" else { return }
    onExitExpandedZone?()
  }

  private func zone(for event: NSEvent) -> String? {
    event.trackingArea?.userInfo?["zone"] as? String
  }

  private static func centeredRect(of size: CGSize, in container: CGSize) -> NSRect {
    NSRect(
      x: (container.width - size.width) / 2,
      y: (container.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
  }
}
