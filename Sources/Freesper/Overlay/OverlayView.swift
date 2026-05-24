import SwiftUI

/// Hover detection lives in `HoverHostingView` (AppKit `NSTrackingArea`).
struct OverlayView: View {
  let model: OverlayState
  @State private var contentOpacity: Double = 0

  /// Lags `model.phase`: the capsule resizes immediately on the live phase,
  /// but the content swap waits for the fade-out so the old content isn't
  /// yanked mid-animation.
  @State private var displayedPhase: OverlayState.Phase = .hint

  private var isExpanded: Bool { model.phase != .idle }
  private var capsuleSize: CGSize {
    switch model.phase {
    case .idle: OverlayMetrics.idleCapsuleSize
    case .hint, .listening: OverlayMetrics.expandedCapsuleSize
    case .transcribing: OverlayMetrics.transcribingCapsuleSize
    }
  }
  private var fillOpacity: Double { isExpanded ? 0.95 : 0.5 }

  var body: some View {
    ZStack {
      Capsule(style: .continuous)
        .fill(Color.black.opacity(fillOpacity))
        .frame(width: capsuleSize.width, height: capsuleSize.height)

      contentRow
        .frame(width: capsuleSize.width, height: capsuleSize.height)
        .clipShape(Capsule(style: .continuous))
        .opacity(contentOpacity)

      Capsule(style: .continuous)
        .stroke(
          isExpanded ? Color(white: 48 / 255) : Color(white: 128 / 255),
          lineWidth: 1
        )
        .frame(width: capsuleSize.width, height: capsuleSize.height)
    }
    .frame(
      width: OverlayMetrics.hostSize.width,
      height: OverlayMetrics.hostSize.height,
      alignment: .center
    )
    .animation(.easeInOut(duration: 0.22), value: model.phase)
    .onChange(of: model.phase, initial: true) { oldPhase, newPhase in
      syncContent(from: oldPhase, to: newPhase)
    }
  }

  private func syncContent(
    from oldPhase: OverlayState.Phase,
    to newPhase: OverlayState.Phase
  ) {
    switch (oldPhase, newPhase) {
    case (_, .idle):
      withAnimation(.easeIn(duration: 0.08)) { contentOpacity = 0 }

    case (.idle, _):
      displayedPhase = newPhase
      withAnimation(.easeInOut(duration: 0.12).delay(0.10)) { contentOpacity = 1 }

    default:
      withAnimation(.easeIn(duration: 0.10)) {
        contentOpacity = 0
      } completion: {
        guard model.phase == newPhase else { return }
        displayedPhase = newPhase
        withAnimation(.easeOut(duration: 0.12)) { contentOpacity = 1 }
      }
    }
  }

  @ViewBuilder
  private var contentRow: some View {
    switch displayedPhase {
    case .hint:
      HintRow(label: model.hotkeyLabel)
    case .listening:
      WaveformView(bars: model.barIntensities)
        .padding(.horizontal, 16)
    case .transcribing:
      TranscribingSpinner()
    case .idle:
      // Unreachable: `displayedPhase` only ever holds non-idle values.
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

private struct TranscribingSpinner: View {
  @State private var rotation = 0.0

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.7)
      .stroke(
        Color.white.opacity(0.92),
        style: StrokeStyle(lineWidth: 2, lineCap: .round)
      )
      .frame(width: 16, height: 16)
      .rotationEffect(.degrees(rotation))
      .onAppear {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
          rotation = 360
        }
      }
  }
}
