import OSLog
import SwiftUI

@main
struct FreesperApp: App {
  @State private var graph = AppGraph()

  var body: some Scene {
    MenuBarExtra {
      Button("Open Setup…") { graph.setupCoordinator.openFromMenu() }
      OpenSettingsMenuButton()
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
      MenuBarLabel(graph: graph)
    }
    .menuBarExtraStyle(.menu)

    Window("Setup", id: SetupWindow.id) {
      SetupView(
        readiness: graph.readiness,
        modelManager: graph.modelManager,
        coordinator: graph.setupCoordinator
      )
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView(
        preferences: graph.preferences,
        deviceCatalog: graph.deviceCatalog
      )
    }
  }
}

/// `LSUIElement` accessory apps don't auto-activate when a window opens, so a
/// plain `SettingsLink` ends up showing the window without key-window focus.
/// Activating *before* `openSettings()` makes the new window come up keyed
/// and focusable.
private struct OpenSettingsMenuButton: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("Settings…") {
      NSApp.activate(ignoringOtherApps: true)
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
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some View {
    Image(systemName: graph.readiness.iconName)
      .onAppear {
        graph.setupCoordinator.openWindow = { openWindow(id: SetupWindow.id) }
        graph.setupCoordinator.dismissWindow = { dismissWindow(id: SetupWindow.id) }
        graph.runOnce()
      }
  }
}
