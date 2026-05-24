import OSLog
import SwiftUI

@main
struct FreesperApp: App {
  @State private var graph = AppGraph()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu(graph: graph)
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

    Window("Welcome to Freesper", id: OnboardingWindow.id) {
      OnboardingView(
        coordinator: graph.onboardingCoordinator,
        readiness: graph.readiness,
        preferences: graph.preferences,
        modelManager: graph.modelManager,
        lastTranscriptStore: graph.lastTranscriptStore,
        activationPolicy: graph.activationPolicy,
        log: graph.log
      )
    }
    .windowResizability(.contentSize)
  }
}

private struct MenuBarMenu: View {
  let graph: AppGraph

  var body: some View {
    if graph.preferences.hasCompletedOnboarding {
      let lastTranscript = graph.lastTranscriptStore.text
      Button("Copy last transcript") {
        if let lastTranscript { PasteService.copyOnly(lastTranscript) }
      }
      .disabled(lastTranscript == nil)
      Divider()
      Button("Settings…") { graph.mainWindowCoordinator.open(.settings) }
    } else {
      Button("Continue Setup…") { graph.onboardingCoordinator.openFromMenu() }
    }
    Button("About") { graph.mainWindowCoordinator.open(.about) }
    Divider()
    Button("Quit") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
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
        graph.onboardingCoordinator.openWindow = { openWindow(id: OnboardingWindow.id) }
        graph.onboardingCoordinator.dismissWindow = { dismissWindow(id: OnboardingWindow.id) }
        graph.mainWindowCoordinator.bind { openWindow(id: MainWindow.id) }
        appDelegate.onReopen = {
          if graph.preferences.hasCompletedOnboarding && graph.readiness.isReady {
            graph.mainWindowCoordinator.open(.settings)
          } else {
            graph.onboardingCoordinator.openFromMenu()
          }
        }
        graph.runOnce()
      }
  }
}
