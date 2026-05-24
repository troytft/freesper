import SwiftUI

struct HotkeyStep: View {
  @Bindable var preferences: Preferences

  var body: some View {
    OnboardingStepChrome(
      systemImage: "keyboard",
      title: "Choose your hotkey",
      description:
        "Pick a key combination to start dictating. Hold it while you speak."
    ) {
      Picker("Hotkey", selection: $preferences.hotkeyPreset) {
        ForEach(HotkeyPreset.allCases, id: \.self) { preset in
          Text(preset.label).tag(preset)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: 360)
    }
  }
}
