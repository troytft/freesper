import SwiftUI

@MainActor
@Observable
final class OnboardingCoordinator {
  var currentStep: OnboardingStep = .welcome
  var isWindowVisible: Bool = false

  @ObservationIgnored private let readiness: AppReadiness
  @ObservationIgnored private let preferences: Preferences
  @ObservationIgnored private let overlay: OverlayController
  @ObservationIgnored private let activationPolicy: ActivationPolicyController

  @ObservationIgnored var openWindow: (() -> Void)?
  @ObservationIgnored var dismissWindow: (() -> Void)?

  init(
    readiness: AppReadiness,
    preferences: Preferences,
    overlay: OverlayController,
    activationPolicy: ActivationPolicyController
  ) {
    self.readiness = readiness
    self.preferences = preferences
    self.overlay = overlay
    self.activationPolicy = activationPolicy
  }

  func start() {
    syncOverlay()
    if !preferences.hasCompletedOnboarding || !readiness.isReady {
      present(desiredStep())
    }
    observeReadiness()
  }

  func openFromMenu() {
    present(desiredStep())
  }

  func continueFromCurrentStep() {
    move(by: 1)
  }

  func back() {
    move(by: -1)
  }

  func finish() {
    preferences.hasCompletedOnboarding = true
    dismissWindow?()
  }

  func windowDidAppear() {
    isWindowVisible = true
  }

  func windowDidDisappear() {
    isWindowVisible = false
  }

  private func observeReadiness() {
    observe { [weak self] in
      _ = self?.readiness.isReady
    } onChange: { [weak self] in
      self?.handleReadinessChange()
    }
  }

  // After the user finishes onboarding, dropped permissions are surfaced
  // elsewhere (overlay/beep on hotkey) — we don't auto-reopen this window,
  // which would feel like a haunting.
  private func handleReadinessChange() {
    syncOverlay()
    guard !readiness.isReady else { return }
    if isWindowVisible {
      snapBackIfNeeded()
    } else if !preferences.hasCompletedOnboarding {
      present(desiredStep())
    }
  }

  private func snapBackIfNeeded() {
    let order = OnboardingStep.allCases
    guard
      let firstBroken = order.first(where: { !$0.isSatisfied(readiness) }),
      let currentIndex = order.firstIndex(of: currentStep),
      let brokenIndex = order.firstIndex(of: firstBroken),
      currentIndex > brokenIndex
    else { return }
    currentStep = firstBroken
  }

  private func desiredStep() -> OnboardingStep {
    if !preferences.hasCompletedOnboarding {
      return .welcome
    }
    return firstNotSatisfied() ?? .welcome
  }

  private func firstNotSatisfied() -> OnboardingStep? {
    OnboardingStep.allCases.first { !$0.isSatisfied(readiness) }
  }

  private func move(by delta: Int) {
    let order = OnboardingStep.allCases
    guard let index = order.firstIndex(of: currentStep) else { return }
    let next = index + delta
    guard order.indices.contains(next) else { return }
    currentStep = order[next]
  }

  private func present(_ step: OnboardingStep) {
    currentStep = step
    activationPolicy.activate()
    openWindow?()
  }

  private func syncOverlay() {
    if readiness.isReady {
      overlay.start()
    } else {
      overlay.stop()
    }
  }
}
