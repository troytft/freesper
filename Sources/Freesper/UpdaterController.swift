import AppKit
import Sparkle

@MainActor
final class UpdaterController: NSObject {
  private let activationPolicy: ActivationPolicyController
  private var controller: SPUStandardUpdaterController!

  init(activationPolicy: ActivationPolicyController) {
    self.activationPolicy = activationPolicy
    super.init()
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: self
    )
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}

extension UpdaterController: @preconcurrency SPUStandardUserDriverDelegate {
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    activationPolicy.acquire(.softwareUpdate)
  }

  func standardUserDriverWillFinishUpdateSession() {
    activationPolicy.release(.softwareUpdate)
  }
}
