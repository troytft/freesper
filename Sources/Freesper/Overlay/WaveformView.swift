import SwiftUI

struct WaveformView: View {
  var bars: [Float]

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
    .animation(.interpolatingSpring(duration: 0.15, bounce: 0), value: bars)
  }

  private func barHeight(at index: Int) -> CGFloat {
    let intensity = index < bars.count ? bars[index] : 0
    return minBarHeight + (maxBarHeight - minBarHeight) * CGFloat(intensity)
  }
}
