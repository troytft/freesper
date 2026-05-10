import SwiftUI

struct SetupView: View {
  let readiness: AppReadiness
  let modelManager: ModelManager
  let coordinator: SetupCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Set up Freesper")
          .font(.title2.weight(.semibold))
        Text("Three things need to be in place before push-to-talk can work.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 12) {
        MicrophoneRow(status: readiness.mic)
        AccessibilityRow(status: readiness.accessibility)
        ModelRow(state: readiness.model, manager: modelManager)
      }

      Divider()

      HStack {
        Image(systemName: readiness.isReady ? "checkmark.circle.fill" : "circle.dotted")
          .foregroundStyle(readiness.isReady ? .green : .secondary)
        Text(
          readiness.isReady
            ? "All set — you can close this window." : "Waiting for the items above."
        )
        .font(.callout)
        .foregroundStyle(readiness.isReady ? .primary : .secondary)
        Spacer()
        if readiness.isReady {
          Button("Close") {
            coordinator.closeFromUser()
          }
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(24)
    .frame(width: 460)
  }
}

private struct MicrophoneRow: View {
  let status: PermissionStatus

  var body: some View {
    SetupRow(
      title: "Microphone access",
      description: "Required to capture audio while you hold the push-to-talk hotkey.",
      isReady: status == .granted
    ) {
      if status != .granted {
        Button("Open System Settings") {
          SystemSettings.open(.microphone)
        }
      }
    }
  }
}

private struct AccessibilityRow: View {
  let status: PermissionStatus

  var body: some View {
    SetupRow(
      title: "Accessibility access",
      description: "Required to paste the transcript into the focused app.",
      isReady: status == .granted
    ) {
      if status != .granted {
        Button("Open System Settings") {
          SystemSettings.open(.accessibility)
        }
      }
    }
  }
}

private struct ModelRow: View {
  let state: ModelState
  let manager: ModelManager

  var body: some View {
    SetupRow(
      title: "Speech model",
      description:
        "Freesper uses Parakeet for on-device transcription. The model downloads automatically on first launch.",
      isReady: isReady
    ) {
      if case .failed = state {
        Button("Retry") { manager.retry() }
      }
    } footer: {
      switch state {
      case .notDownloaded:
        progressBar(value: 0, label: "Starting…")
      case .downloading(let progress):
        progressBar(value: progress, label: percent(progress))
      case .failed(let error):
        Text(error.localizedDescription)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
      case .ready:
        EmptyView()
      }
    }
  }

  private func progressBar(value: Double, label: String) -> some View {
    HStack(spacing: 8) {
      ProgressView(value: max(0, min(1, value)))
        .progressViewStyle(.linear)
      Text(label)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(minWidth: 36, alignment: .trailing)
    }
  }

  private var isReady: Bool {
    if case .ready = state { return true }
    return false
  }

  private func percent(_ fraction: Double) -> String {
    let clamped = max(0, min(1, fraction))
    return "\(Int((clamped * 100).rounded()))%"
  }
}

/// Trailing slot is hidden when the item is satisfied so the row collapses
/// to a quiet ✓.
private struct SetupRow<Trailing: View, Footer: View>: View {
  let title: String
  let description: String
  let isReady: Bool
  @ViewBuilder var trailing: () -> Trailing
  @ViewBuilder var footer: () -> Footer

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 18))
          .foregroundStyle(isReady ? .green : .secondary)
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline)
          Text(description)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 12)

        HStack(spacing: 8) {
          trailing()
        }
      }

      // Indent under the title so the progress bar lines up with the
      // text instead of starting under the status icon.
      footer()
        .padding(.leading, 30)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}

extension SetupRow where Footer == EmptyView {
  init(
    title: String,
    description: String,
    isReady: Bool,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.init(
      title: title,
      description: description,
      isReady: isReady,
      trailing: trailing,
      footer: { EmptyView() }
    )
  }
}
