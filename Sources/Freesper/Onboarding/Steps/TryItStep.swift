import SwiftUI

struct TryItStep: View {
  let preferences: Preferences
  let lastTranscriptStore: LastTranscriptStore

  // TextEditor needs a binding; nothing reads this value — the field
  // exists only to receive the simulated paste from PasteService.
  @State private var sandboxText: String = ""
  @State private var baselineVersion: Int = 0
  @State private var didDictate: Bool = false
  @FocusState private var isFocused: Bool

  var body: some View {
    OnboardingStepChrome(
      systemImage: "waveform",
      title: "Try it",
      description:
        "Press and hold \(preferences.hotkeyPreset.label) and say something. Your words will appear in the field below."
    ) {
      VStack(spacing: 10) {
        TextEditor(text: $sandboxText)
          .font(.body)
          .focused($isFocused)
          .frame(minHeight: 120, maxHeight: 160)
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
          )
          .frame(maxWidth: 420)

        if didDictate {
          Label("Got it", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.callout)
        }
      }
    }
    .onAppear {
      baselineVersion = lastTranscriptStore.version
      isFocused = true
    }
    .onChange(of: lastTranscriptStore.version) { _, newVersion in
      if newVersion > baselineVersion {
        didDictate = true
      }
    }
  }
}
