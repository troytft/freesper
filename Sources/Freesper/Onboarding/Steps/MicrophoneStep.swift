import SwiftUI

struct MicrophoneStep: View {
  let readiness: AppReadiness

  var body: some View {
    OnboardingStepChrome(
      systemImage: "mic.fill",
      title: "Microphone access",
      description:
        "Freesper records only while your hotkey is held. Audio is processed locally and never leaves your Mac."
    ) {
      VStack(spacing: 14) {
        actionView
        statusView
      }
    }
  }

  @ViewBuilder
  private var actionView: some View {
    switch readiness.mic {
    case .granted:
      EmptyView()
    case .notDetermined:
      Button("Allow Microphone Access") {
        Task { @MainActor in
          readiness.mic = await MicrophonePermission.request()
        }
      }
      .controlSize(.large)
      .buttonStyle(.borderedProminent)
    case .denied:
      VStack(spacing: 8) {
        Button("Open System Settings") {
          SystemSettings.open(.microphone)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        Text("Toggle Freesper in the list, then come back.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var statusView: some View {
    if readiness.mic == .granted {
      Label("Microphone access granted", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout)
    }
  }
}
