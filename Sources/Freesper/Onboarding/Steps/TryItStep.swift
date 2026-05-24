import SwiftUI

struct TryItStep: View {
  let preferences: Preferences
  let lastTranscriptStore: LastTranscriptStore

  @State private var draft: String = ""
  @State private var baseline: String?
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
        TextEditor(text: $draft)
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
      baseline = lastTranscriptStore.text
      isFocused = true
    }
    .onChange(of: lastTranscriptStore.text) { _, newValue in
      guard let newValue, newValue != baseline else { return }
      didDictate = true
    }
  }
}
