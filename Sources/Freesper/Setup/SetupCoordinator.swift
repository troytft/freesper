import SwiftUI

/// Coordinates the Setup window: tracks who last opened it so we know whether
/// to auto-dismiss on a ready-up, and reacts to readiness changes by
/// presenting/dismissing the window and starting/stopping the overlay.
///
/// SwiftUI views drive the window via `openWindow`/`dismissWindow`, but those
/// only work from a `View` context. The coordinator therefore holds two
/// closures it asks the view layer to wire up at first appearance.
@MainActor
@Observable
final class SetupCoordinator {
  /// True iff the most recent open call came from us reacting to a readiness
  /// drop. Cleared when the user opens the window themselves so we don't
  /// dismiss it from under them.
  var openedBySystem: Bool = false

  @ObservationIgnored
  private let readiness: AppReadiness
  @ObservationIgnored
  private let overlay: OverlayController
  @ObservationIgnored
  private let activationPolicy: ActivationPolicyController

  /// Provided by the SwiftUI layer once it has access to the environment
  /// `openWindow` / `dismissWindow` actions.
  @ObservationIgnored
  var openWindow: (() -> Void)?
  @ObservationIgnored
  var dismissWindow: (() -> Void)?

  init(
    readiness: AppReadiness,
    overlay: OverlayController,
    activationPolicy: ActivationPolicyController
  ) {
    self.readiness = readiness
    self.overlay = overlay
    self.activationPolicy = activationPolicy
  }

  /// Called once the SwiftUI environment actions are available. Performs
  /// the initial sync and arms an observer for future readiness flips.
  func start() {
    syncToReadiness()
    observeReadiness()
  }

  /// Called from the menu "Open Setup…" item.
  func openFromMenu() {
    openedBySystem = false
    activationPolicy.activate()
    openWindow?()
  }

  /// Called from the in-window "Close" button.
  func closeFromUser() {
    dismissWindow?()
    openedBySystem = false
  }

  private func observeReadiness() {
    observe { [weak self] in
      _ = self?.readiness.isReady
    } onChange: { [weak self] in
      self?.syncToReadiness()
    }
  }

  private func syncToReadiness() {
    if readiness.isReady {
      overlay.start()
      if openedBySystem {
        dismissWindow?()
        openedBySystem = false
      }
    } else {
      overlay.stop()
      activationPolicy.activate()
      openWindow?()
      openedBySystem = true
    }
  }
}
