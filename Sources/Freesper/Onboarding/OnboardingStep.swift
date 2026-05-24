enum OnboardingStep: Int, CaseIterable {
  case welcome
  case microphone
  case accessibility
  case model
  case hotkey
  case tryIt

  /// "Satisfied" means the step poses no blocking condition for advancing.
  /// Informational steps (welcome, hotkey, tryIt) are always satisfied;
  /// permission/model steps gate on actual readiness.
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
