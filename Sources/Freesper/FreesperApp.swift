import OSLog
import SwiftUI

@main
struct FreesperApp: App {
  @State private var graph = AppGraph()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      Button("Open Setup…") { graph.setupCoordinator.openFromMenu() }
      OpenSettingsMenuButton(activationPolicy: graph.activationPolicy)
      Divider()
      Button("About") {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
      }
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    } label: {
      MenuBarLabel(graph: graph, appDelegate: appDelegate)
    }
    .menuBarExtraStyle(.menu)

    Window("Setup", id: SetupWindow.id) {
      SetupView(
        readiness: graph.readiness,
        modelManager: graph.modelManager,
        coordinator: graph.setupCoordinator,
        activationPolicy: graph.activationPolicy
      )
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView(
        preferences: graph.preferences,
        deviceCatalog: graph.deviceCatalog,
        activationPolicy: graph.activationPolicy
      )
    }
  }
}

/// `SettingsLink` doesn't activate the app before showing the window, so on
/// LSUIElement builds the new window comes up without key focus. Pre-activate
/// via the policy controller so it appears keyed.
private struct OpenSettingsMenuButton: View {
  let activationPolicy: ActivationPolicyController
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("Settings…") {
      activationPolicy.activate()
      openSettings()
    }
  }
}

/// Lives inside the menu bar `label:` slot — always present in the SwiftUI
/// view tree as long as the app is running. That makes it the right place to
/// publish `openWindow`/`dismissWindow` environment actions to the
/// `SetupCoordinator` and to kick off the one-time bootstrap.
private struct MenuBarLabel: View {
  let graph: AppGraph
  let appDelegate: AppDelegate
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Image(systemName: graph.readiness.iconName)
      .onAppear {
        graph.setupCoordinator.openWindow = { openWindow(id: SetupWindow.id) }
        graph.setupCoordinator.dismissWindow = { dismissWindow(id: SetupWindow.id) }
        appDelegate.onReopen = { [graph, openWindow, openSettings] in
          graph.activationPolicy.activate()
          if graph.readiness.isReady {
            openSettings()
          } else {
            openWindow(id: SetupWindow.id)
          }
        }
        graph.runOnce()
      }
  }
}
