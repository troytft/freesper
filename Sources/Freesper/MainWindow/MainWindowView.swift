import SwiftUI

struct MainWindowView: View {
  let coordinator: MainWindowCoordinator
  let preferences: Preferences
  let deviceCatalog: AudioDeviceCatalog
  let activationPolicy: ActivationPolicyController

  var body: some View {
    NavigationSplitView {
      List(selection: sidebarSelection) {
        ForEach(MainSection.allCases) { section in
          Label(section.label, systemImage: section.systemImage)
            .tag(section)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    } detail: {
      detail
        .navigationTitle(coordinator.selectedSection.label)
    }
    .onAppear { activationPolicy.acquire(.mainWindow) }
    .onDisappear { activationPolicy.release(.mainWindow) }
  }

  private var sidebarSelection: Binding<MainSection?> {
    Binding(
      get: { coordinator.selectedSection },
      set: { if let new = $0 { coordinator.selectedSection = new } }
    )
  }

  @ViewBuilder
  private var detail: some View {
    switch coordinator.selectedSection {
    case .settings:
      SettingsView(preferences: preferences, deviceCatalog: deviceCatalog)
    case .about:
      AboutView()
    #if DEBUG
      case .developer:
        DeveloperView()
    #endif
    }
  }
}
