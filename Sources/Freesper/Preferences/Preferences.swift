import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
  private let defaults: UserDefaults

  /// Core Audio device UID of the user's preferred microphone. `nil` means
  /// "follow the system default input" — the same behaviour you'd get if
  /// AVAudioEngine were left untouched.
  var microphoneUID: String? {
    didSet {
      guard oldValue != microphoneUID else { return }
      defaults.set(microphoneUID, forKey: Keys.microphoneUID)
    }
  }

  var hotkeyPreset: HotkeyPreset {
    didSet {
      guard oldValue != hotkeyPreset else { return }
      defaults.set(hotkeyPreset.rawValue, forKey: Keys.hotkeyPreset)
    }
  }

  /// Independent from `hotkeyPreset` — same binding can be hold or toggle.
  var hotkeyMode: HotkeyMode {
    didSet {
      guard oldValue != hotkeyMode else { return }
      defaults.set(hotkeyMode.rawValue, forKey: Keys.hotkeyMode)
    }
  }

  var showDockIcon: Bool {
    didSet {
      guard oldValue != showDockIcon else { return }
      defaults.set(showDockIcon, forKey: Keys.showDockIcon)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.microphoneUID = defaults.string(forKey: Keys.microphoneUID)
    self.hotkeyPreset =
      defaults.string(forKey: Keys.hotkeyPreset)
      .flatMap(HotkeyPreset.init(rawValue:)) ?? .default
    self.hotkeyMode =
      defaults.string(forKey: Keys.hotkeyMode)
      .flatMap(HotkeyMode.init(rawValue:)) ?? .hold
    self.showDockIcon =
      (defaults.object(forKey: Keys.showDockIcon) as? Bool) ?? true
  }

  private enum Keys {
    static let microphoneUID = "preferences.microphoneUID"
    static let hotkeyPreset = "preferences.hotkeyPreset"
    static let hotkeyMode = "preferences.hotkeyMode"
    static let showDockIcon = "preferences.showDockIcon"
  }
}
