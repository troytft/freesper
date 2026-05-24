import SwiftUI

@MainActor
@Observable
final class OnboardingCoordinator {
  var currentStep: OnboardingStep = .welcome
  var isWindowVisible: Bool = false

  @ObservationIgnored
  private let readiness: AppReadiness
  @ObservationIgnored
  private let preferences: Preferences
  @ObservationIgnored
  private let overlay: OverlayController
  @ObservationIgnored
  private let activationPolicy: ActivationPolicyController

  @ObservationIgnored
  var openWindow: (() -> Void)?
  @ObservationIgnored
  var dismissWindow: (() -> Void)?

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
    applyInitialDecision()
    observeReadiness()
  }

  func openFromMenu() {
    currentStep = stepForOpen()
    activationPolicy.activate()
    openWindow?()
  }

  func continueFromCurrentStep() {
    let order = OnboardingStep.allCases
    guard let index = order.firstIndex(of: currentStep), index < order.count - 1 else {
      return
    }
    currentStep = order[index + 1]
  }

  func back() {
    let order = OnboardingStep.allCases
    guard let index = order.firstIndex(of: currentStep), index > 0 else {
      return
    }
    currentStep = order[index - 1]
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

  private func applyInitialDecision() {
    if !preferences.hasCompletedOnboarding {
      currentStep = .welcome
      activationPolicy.activate()
      openWindow?()
      return
    }
    if !readiness.isReady {
      currentStep = firstNotSatisfied() ?? .welcome
      activationPolicy.activate()
      openWindow?()
    }
  }

  private func observeReadiness() {
    observe { [weak self] in
      _ = self?.readiness.isReady
    } onChange: { [weak self] in
      self?.handleReadinessChange()
    }
  }

  private func handleReadinessChange() {
    syncOverlay()
    guard !readiness.isReady else { return }
    if isWindowVisible {
      snapBackIfNeeded()
    } else {
      currentStep = firstNotSatisfied() ?? .welcome
      activationPolicy.activate()
      openWindow?()
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

  private func stepForOpen() -> OnboardingStep {
    if !preferences.hasCompletedOnboarding {
      return .welcome
    }
    return firstNotSatisfied() ?? .welcome
  }

  private func firstNotSatisfied() -> OnboardingStep? {
    OnboardingStep.allCases.first { !$0.isSatisfied(readiness) }
  }

  private func syncOverlay() {
    if readiness.isReady {
      overlay.start()
    } else {
      overlay.stop()
    }
  }
}
