enum MainSection: Hashable, CaseIterable, Identifiable {
  case home
  case history
  case settings
  case about
  #if DEBUG
    case developer
  #endif

  var id: Self { self }

  var label: String {
    switch self {
    case .home: "Home"
    case .history: "History"
    case .settings: "Settings"
    case .about: "About"
    #if DEBUG
      case .developer: "Developer"
    #endif
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .history: "clock"
    case .settings: "gearshape"
    case .about: "info.circle"
    #if DEBUG
      case .developer: "hammer"
    #endif
    }
  }
}
