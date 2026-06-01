import AppKit
import Sparkle

@MainActor
final class UpdaterController: NSObject {
  private let activationPolicy: ActivationPolicyController
  private var controller: SPUStandardUpdaterController!
  private var hasStarted = false

  init(activationPolicy: ActivationPolicyController) {
    self.activationPolicy = activationPolicy
    super.init()
    controller = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: self,
      userDriverDelegate: self
    )
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    controller.startUpdater()
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}

extension UpdaterController: SPUUpdaterDelegate {
  func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
    true
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
