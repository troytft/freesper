import SwiftUI

struct ModelStep: View {
  let readiness: AppReadiness
  let modelManager: ModelManager

  var body: some View {
    OnboardingStepChrome(
      systemImage: "arrow.down.circle",
      title: "Speech model",
      description: "≈600 MB, downloads once, stays on your Mac."
    ) {
      VStack(spacing: 14) {
        statusView
        actionView
      }
      .frame(maxWidth: 360)
    }
  }

  @ViewBuilder
  private var actionView: some View {
    if case .failed = readiness.model {
      Button("Retry") { modelManager.retry() }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch readiness.model {
    case .notDownloaded:
      progressBar(value: 0, label: "Starting…")
    case .downloading(let progress):
      progressBar(value: progress, label: percent(progress))
    case .failed(let error):
      Text(error.localizedDescription)
        .font(.callout)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    case .ready:
      Label("Model ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout)
    }
  }

  private func progressBar(value: Double, label: String) -> some View {
    HStack(spacing: 10) {
      ProgressView(value: max(0, min(1, value)))
        .progressViewStyle(.linear)
      Text(label)
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(minWidth: 44, alignment: .trailing)
    }
  }

  private func percent(_ fraction: Double) -> String {
    let clamped = max(0, min(1, fraction))
    return "\(Int((clamped * 100).rounded()))%"
  }
}
