import SwiftUI

/// Hover detection lives in `HoverHostingView` (AppKit `NSTrackingArea`).
struct OverlayView: View {
  let model: OverlayState
  @State private var contentOpacity: Double = 0

  private var isExpanded: Bool { model.phase != .idle }
  private var capsuleWidth: CGFloat {
    isExpanded ? OverlayMetrics.expandedCapsuleSize.width : OverlayMetrics.idleCapsuleSize.width
  }
  private var capsuleHeight: CGFloat {
    isExpanded ? OverlayMetrics.expandedCapsuleSize.height : OverlayMetrics.idleCapsuleSize.height
  }

  var body: some View {
    ZStack {
      Capsule(style: .continuous)
        .fill(Color.black)
        .frame(width: capsuleWidth, height: capsuleHeight)

      contentRow
        .frame(width: capsuleWidth, height: capsuleHeight)
        .clipShape(Capsule(style: .continuous))
        .opacity(contentOpacity)

      Capsule(style: .continuous)
        .stroke(
          isExpanded
            ? Color(red: 48 / 255, green: 48 / 255, blue: 47 / 255)
            : Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255),
          lineWidth: 1
        )
        .frame(width: capsuleWidth, height: capsuleHeight)
    }
    .frame(
      width: OverlayMetrics.hostSize.width,
      height: OverlayMetrics.hostSize.height,
      alignment: .center
    )
    .animation(.easeInOut(duration: 0.22), value: model.phase)
    .onChange(of: isExpanded) { _, expanded in
      if expanded {
        withAnimation(.easeInOut(duration: 0.12).delay(0.10)) {
          contentOpacity = 1
        }
      } else {
        withAnimation(.easeIn(duration: 0.08)) {
          contentOpacity = 0
        }
      }
    }
  }

  @ViewBuilder
  private var contentRow: some View {
    switch model.lastVisiblePhase {
    case .hint:
      HintRow(label: model.hotkeyLabel)
    case .listening:
      WaveformView(levels: model.levels, phase: .listening)
        .padding(.horizontal, 16)
    case .transcribing:
      TranscribingShimmer()
        .padding(.horizontal, 16)
    case .idle:
      // Unreachable: `lastVisiblePhase` only stores non-idle values.
      EmptyView()
    }
  }
}

private struct HintRow: View {
  let label: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "mic.fill")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
      (Text("Press ")
        + Text(label.isEmpty ? "—" : label).fontWeight(.semibold))
        .foregroundColor(.white)
        .font(.system(size: 12))
        .lineLimit(1)
        // Keep text at intrinsic size during the capsule shrink animation;
        // without it SwiftUI re-runs truncation each frame and the text wobbles.
        .fixedSize()
    }
    .padding(.horizontal, 14)
  }
}
