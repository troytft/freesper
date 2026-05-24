import OSLog
import SwiftUI

struct AccessibilityStep: View {
  let readiness: AppReadiness
  let log: Logger

  var body: some View {
    OnboardingStepChrome(
      systemImage: "accessibility",
      title: "Accessibility access",
      description:
        "Freesper needs Accessibility to paste the transcript into the app you're using."
    ) {
      VStack(spacing: 14) {
        actionView
        statusView
      }
    }
  }

  @ViewBuilder
  private var actionView: some View {
    if readiness.accessibility != .granted {
      VStack(spacing: 8) {
        Button("Open System Settings") {
          AccessibilityPermission.ensure(prompt: true, log: log)
          SystemSettings.open(.accessibility)
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
    if readiness.accessibility == .granted {
      Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout)
    } else {
      Label("Waiting for permission…", systemImage: "hourglass")
        .foregroundStyle(.secondary)
        .font(.callout)
    }
  }
}
