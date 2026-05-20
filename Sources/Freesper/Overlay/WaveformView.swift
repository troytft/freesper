import SwiftUI

/// Two visual modes packed into one view so the height/width math stays
/// consistent across the listening → transcribing transition:
///
/// - `.listening` — bars are driven by recent RMS levels, oldest on the left,
///   newest on the right. Heights animate smoothly between poll ticks so a
///   30 Hz sample stream still feels fluid.
/// - `.transcribing` — there's no live signal to react to, so the bars become
///   a leftward-flowing sine wave. The motion reassures the user that the app
///   is doing something even when transcription takes a beat.
struct WaveformView: View {
  var levels: [Float]
  var phase: OverlayState.Phase

  static let barCount = 16
  private let barWidth: CGFloat = 3
  private let barSpacing: CGFloat = 3
  private let minBarHeight: CGFloat = 3
  private let maxBarHeight: CGFloat = 18

  var body: some View {
    HStack(alignment: .center, spacing: barSpacing) {
      ForEach(0..<Self.barCount, id: \.self) { index in
        Capsule(style: .continuous)
          .fill(Color.white.opacity(0.92))
          .frame(width: barWidth, height: barHeight(at: index))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: maxBarHeight, alignment: .center)
    .animation(.linear(duration: 0.06), value: levels)
    .animation(.easeInOut(duration: 0.18), value: phase)
  }

  private func barHeight(at index: Int) -> CGFloat {
    switch phase {
    case .listening:
      let raw = index < levels.count ? levels[index] : 0
      return minBarHeight + (maxBarHeight - minBarHeight) * scale(raw)

    case .transcribing, .idle, .hint:
      // Static snapshot off the listening path; the live shimmer is
      // provided by `TranscribingShimmer`, and the other phases don't
      // render the waveform at all.
      return minBarHeight
    }
  }

  private func scale(_ rms: Float) -> CGFloat {
    let noiseFloor: Float = 0.008
    let aboveFloor = max(0, rms - noiseFloor)
    let amplified = min(1, aboveFloor * 6)
    return CGFloat(sqrt(amplified))
  }
}

/// Leftward-flowing sine wave used during the transcribe phase. Re-renders on
/// every animation frame via `TimelineView(.animation)`.
struct TranscribingShimmer: View {
  private let barCount = WaveformView.barCount
  private let barWidth: CGFloat = 3
  private let barSpacing: CGFloat = 3
  private let minBarHeight: CGFloat = 2

  var body: some View {
    TimelineView(.animation) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      GeometryReader { geo in
        HStack(alignment: .center, spacing: barSpacing) {
          ForEach(0..<barCount, id: \.self) { index in
            Capsule(style: .continuous)
              .fill(Color.white.opacity(0.78))
              .frame(
                width: barWidth,
                height: shimmerHeight(
                  at: index,
                  time: t,
                  maxHeight: geo.size.height
                )
              )
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
    }
    .frame(height: 20)
  }

  private func shimmerHeight(at index: Int, time: TimeInterval, maxHeight: CGFloat) -> CGFloat {
    let phase = Double(index) * 0.42 - time * 4.5
    let normalized = (sin(phase) + 1) / 2
    // Bell envelope so the wave dims at the edges and looks centred.
    let envelope = sin(.pi * Double(index) / Double(barCount - 1))
    let unit = normalized * envelope
    return minBarHeight + (maxHeight - minBarHeight) * (0.25 + 0.55 * unit)
  }
}
