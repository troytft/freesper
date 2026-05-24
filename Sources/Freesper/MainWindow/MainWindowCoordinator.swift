import SwiftUI

@MainActor
@Observable
final class MainWindowCoordinator {
  var selectedSection: MainSection = .settings

  @ObservationIgnored
  private let activationPolicy: ActivationPolicyController

  @ObservationIgnored
  private(set) var openWindow: (() -> Void)?

  init(activationPolicy: ActivationPolicyController) {
    self.activationPolicy = activationPolicy
  }

  func bind(openWindow: @escaping () -> Void) {
    self.openWindow = openWindow
  }

  func open() {
    activationPolicy.activate()
    openWindow?()
  }

  func open(_ section: MainSection) {
    selectedSection = section
    open()
  }
}
