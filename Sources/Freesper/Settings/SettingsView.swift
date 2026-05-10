import SwiftUI

struct SettingsView: View {
  let preferences: Preferences
  let deviceCatalog: AudioDeviceCatalog

  var body: some View {
    Form {
      Section("Microphone") {
        MicrophonePicker(
          preferences: preferences,
          deviceCatalog: deviceCatalog
        )
      }

      Section("Push-to-talk") {
        Picker("Hotkey", selection: presetBinding) {
          ForEach(HotkeyPreset.allCases, id: \.self) { preset in
            Text(preset.label).tag(preset)
          }
        }
        .pickerStyle(.menu)

        Picker("Mode", selection: modeBinding) {
          Text("Hold").tag(HotkeyMode.hold)
          Text("Toggle").tag(HotkeyMode.toggle)
        }
        .pickerStyle(.segmented)
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .frame(minHeight: 240)
  }

  private var presetBinding: Binding<HotkeyPreset> {
    Binding(
      get: { preferences.hotkeyPreset },
      set: { preferences.hotkeyPreset = $0 }
    )
  }

  private var modeBinding: Binding<HotkeyMode> {
    Binding(
      get: { preferences.hotkeyMode },
      set: { preferences.hotkeyMode = $0 }
    )
  }
}

private struct MicrophonePicker: View {
  let preferences: Preferences
  let deviceCatalog: AudioDeviceCatalog

  var body: some View {
    Picker("Input device", selection: selectionBinding) {
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

  private var selectionBinding: Binding<String?> {
    Binding(
      get: { preferences.microphoneUID },
      set: { preferences.microphoneUID = $0 }
    )
  }

  private func label(for device: AudioInputDevice) -> String {
    "\(device.name) (\(device.transport.displayLabel))"
  }
}
