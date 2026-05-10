import SwiftUI

@MainActor
@Observable
final class OverlayState {
  enum Phase {
    case idle
    case hint
    case listening
    case transcribing
  }

  /// Tracked separately so that when `phase` returns to `.idle`, the content
  /// keeps rendering through the fade-out animation instead of being yanked
  /// from the view hierarchy the instant the phase flips.
  private(set) var lastVisiblePhase: Phase = .hint

  var phase: Phase = .idle {
    didSet {
      if phase != .idle { lastVisiblePhase = phase }
    }
  }

  /// Recent RMS levels, oldest → newest.
  var levels: [Float] = []
  var hotkeyLabel: String = ""
}

/// Shared sizing constants for the floating pill. The hosting NSView and
/// the SwiftUI capsule pull from the same source so hit-testing always
/// matches what the user sees.
enum OverlayMetrics {
  /// Fixed size of the AppKit hosting view. The SwiftUI capsule inside
  /// resizes; this never does.
  static let hostSize = CGSize(width: 240, height: 40)

  static let idleCapsuleSize = CGSize(width: 48, height: 6)
  static let expandedCapsuleSize = CGSize(width: 140, height: 34)

  /// Tracking rect that fires `onEnterIdleZone`. Larger than the visible
  /// pill so the cursor catches the pill on a casual mouseover.
  static let idleHoverZone = CGSize(width: 80, height: 24)

  /// Slightly wider than the visible pill — the 6 px height is hard to
  /// click pixel-perfect, so we give a small horizontal tolerance.
  static let idleHitTestSize = CGSize(
    width: idleCapsuleSize.width + 8, height: idleCapsuleSize.height)
}
