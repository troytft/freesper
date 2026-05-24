import SwiftUI

struct OnboardingStepChrome<Icon: View, Content: View>: View {
  @ViewBuilder var icon: () -> Icon
  let title: String
  let description: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 20) {
      icon()
        .frame(height: 72)

      VStack(spacing: 8) {
        Text(title)
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)
        Text(description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 24)

      content()

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 128)
    .padding(.horizontal, 24)
  }
}

extension OnboardingStepChrome where Icon == OnboardingSymbolIcon {
  init(
    systemImage: String,
    title: String,
    description: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.init(
      icon: { OnboardingSymbolIcon(systemName: systemImage) },
      title: title,
      description: description,
      content: content
    )
  }
}

struct OnboardingSymbolIcon: View {
  let systemName: String

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 56, weight: .regular))
      .foregroundStyle(.tint)
  }
}
