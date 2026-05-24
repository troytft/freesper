enum OnboardingStep: Int, CaseIterable {
  case welcome
  case microphone
  case accessibility
  case model
  case hotkey
  case tryIt

  @MainActor
  func isSatisfied(_ readiness: AppReadiness) -> Bool {
    switch self {
    case .welcome, .hotkey, .tryIt:
      return true
    case .microphone:
      return readiness.mic == .granted
    case .accessibility:
      return readiness.accessibility == .granted
    case .model:
      return readiness.model.isReady
    }
  }
}
