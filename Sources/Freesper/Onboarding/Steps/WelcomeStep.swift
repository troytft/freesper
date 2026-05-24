import AppKit
import SwiftUI

struct WelcomeStep: View {
  var body: some View {
    OnboardingStepChrome(
      icon: {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 72, height: 72)
      },
      title: "Welcome to Freesper",
      description:
        "Freesper turns what you say into text. It lives in your menu bar — press a hotkey, speak, your words land in whatever app you're using. Everything runs on your Mac.",
      content: { EmptyView() }
    )
  }
}
