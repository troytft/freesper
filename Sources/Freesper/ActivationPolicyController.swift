import AppKit

@MainActor
final class ActivationPolicyController {
  enum Reason: Hashable {
    case userPreference
    case onboarding
    case mainWindow
  }

  private var reasons: Set<Reason> = []

  init() {
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.demoteIfIdle()
      }
    }
  }

  func acquire(_ reason: Reason) {
    guard reasons.insert(reason).inserted else { return }
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    if reason != .userPreference, !NSApp.isActive {
      NSRunningApplication.current.activate(options: .activateAllWindows)
    }
  }

  func release(_ reason: Reason) {
    reasons.remove(reason)
  }

  func activate() {
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    if !NSApp.isActive {
      NSRunningApplication.current.activate(options: .activateAllWindows)
    }
  }

  // Demoting from SwiftUI's `onDisappear` flickers the menu bar — the
  // closing window is still key at that point. Wait for AppKit's own
  // close notification so the demote lands after the window is gone.
  private func demoteIfIdle() {
    guard reasons.isEmpty else { return }
    guard NSApp.activationPolicy() == .regular else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
