import OSLog
import SwiftUI

struct OnboardingView: View {
  let coordinator: OnboardingCoordinator
  let readiness: AppReadiness
  let preferences: Preferences
  let modelManager: ModelManager
  let lastTranscriptStore: LastTranscriptStore
  let activationPolicy: ActivationPolicyController
  let log: Logger

  private static let contentSize = CGSize(width: 580, height: 520)

  var body: some View {
    VStack(spacing: 0) {
      stepContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      ProgressStrip(current: coordinator.currentStep)
        .padding(.bottom, 14)

      navRow
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
    .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    .onAppear {
      activationPolicy.acquire(.onboarding)
      coordinator.windowDidAppear()
    }
    .onDisappear {
      activationPolicy.release(.onboarding)
      coordinator.windowDidDisappear()
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch coordinator.currentStep {
    case .welcome:
      WelcomeStep()
    case .microphone:
      MicrophoneStep(readiness: readiness)
    case .accessibility:
      AccessibilityStep(readiness: readiness, log: log)
    case .model:
      ModelStep(readiness: readiness, modelManager: modelManager)
    case .hotkey:
      HotkeyStep(preferences: preferences)
    case .tryIt:
      TryItStep(preferences: preferences, lastTranscriptStore: lastTranscriptStore)
    }
  }

  private var navRow: some View {
    HStack {
      if coordinator.currentStep != .welcome {
        Button("Back") { coordinator.back() }
          .keyboardShortcut(.cancelAction)
      }
      Spacer()
      if coordinator.currentStep == .tryIt {
        Button("Finish") { coordinator.finish() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      } else {
        Button("Continue") { coordinator.continueFromCurrentStep() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(!coordinator.currentStep.isSatisfied(readiness))
      }
    }
  }
}

private struct ProgressStrip: View {
  let current: OnboardingStep

  var body: some View {
    let order = OnboardingStep.allCases
    let currentIndex = order.firstIndex(of: current) ?? 0
    HStack(spacing: 8) {
      ForEach(Array(order.enumerated()), id: \.element) { index, _ in
        Circle()
          .fill(index <= currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
          .frame(width: 6, height: 6)
      }
    }
    .frame(maxWidth: .infinity)
  }
}
