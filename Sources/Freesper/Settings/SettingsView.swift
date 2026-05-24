import SwiftUI

struct SettingsView: View {
  @Bindable var preferences: Preferences
  let deviceCatalog: AudioDeviceCatalog

  var body: some View {
    Form {
      Section("General") {
        Toggle("Show in Dock", isOn: $preferences.showDockIcon)
      }

      Section("Microphone") {
        MicrophonePicker(
          preferences: preferences,
          deviceCatalog: deviceCatalog
        )
      }

      Section("Push-to-talk") {
        Picker("Hotkey", selection: $preferences.hotkeyPreset) {
          ForEach(HotkeyPreset.allCases, id: \.self) { preset in
            Text(preset.label).tag(preset)
          }
        }
        .pickerStyle(.menu)
      }
    }
    .formStyle(.grouped)
  }
}

private struct MicrophonePicker: View {
  @Bindable var preferences: Preferences
  let deviceCatalog: AudioDeviceCatalog

  var body: some View {
    Picker("Input device", selection: $preferences.microphoneUID) {
      Text("System default").tag(String?.none)
      ForEach(deviceCatalog.devices) { device in
        Text(label(for: device)).tag(String?.some(device.uid))
      }

      // If the stored UID doesn't match any present device, surface it
      // as a disabled "Unavailable" row so the picker has *something*
      // to display for the current selection — otherwise SwiftUI shows
      // an empty picker and the user can't tell what's happening.
      if let uid = preferences.microphoneUID,
        !deviceCatalog.devices.contains(where: { $0.uid == uid })
      {
        Text("Previously selected — not connected").tag(String?.some(uid))
      }
    }
    .pickerStyle(.menu)
  }

  private func label(for device: AudioInputDevice) -> String {
    "\(device.name) (\(device.transport.displayLabel))"
  }
}
