import OSLog
import SwiftUI

@main
struct FreesperApp: App {
  @State private var graph = AppGraph()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      let lastTranscript = graph.lastTranscriptStore.text
      Button("Copy last transcript") {
        if let lastTranscript { PasteService.copyOnly(lastTranscript) }
      }
      .disabled(lastTranscript == nil)
      Divider()
      Button("Settings…") { graph.mainWindowCoordinator.open(.settings) }
      Button("About") { graph.mainWindowCoordinator.open(.about) }
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    } label: {
      MenuBarLabel(graph: graph, appDelegate: appDelegate)
    }
    .menuBarExtraStyle(.menu)

    Window("Freesper", id: MainWindow.id) {
      MainWindowView(
        coordinator: graph.mainWindowCoordinator,
        preferences: graph.preferences,
        deviceCatalog: graph.deviceCatalog,
        activationPolicy: graph.activationPolicy
      )
    }
    .defaultSize(width: 900, height: 600)
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { graph.mainWindowCoordinator.open(.settings) }
          .keyboardShortcut(",")
      }
    }

    Window("Setup", id: SetupWindow.id) {
      SetupView(
        readiness: graph.readiness,
        modelManager: graph.modelManager,
        coordinator: graph.setupCoordinator,
        activationPolicy: graph.activationPolicy
      )
    }
    .windowResizability(.contentSize)
  }
}

/// Lives inside the menu bar `label:` slot — always present in the SwiftUI
/// view tree as long as the app is running. That makes it the right place to
/// publish `openWindow`/`dismissWindow` environment actions to the
/// window coordinators and to kick off the one-time bootstrap.
private struct MenuBarLabel: View {
  let graph: AppGraph
  let appDelegate: AppDelegate
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some View {
    Image("MenuBarIcon")
      .onAppear {
        graph.setupCoordinator.openWindow = { openWindow(id: SetupWindow.id) }
        graph.setupCoordinator.dismissWindow = { dismissWindow(id: SetupWindow.id) }
        graph.mainWindowCoordinator.bind { openWindow(id: MainWindow.id) }
        appDelegate.onReopen = { [graph] in
          if graph.readiness.isReady {
            graph.mainWindowCoordinator.open(.settings)
          } else {
            graph.setupCoordinator.openFromMenu()
          }
        }
        graph.runOnce()
      }
  }
}
