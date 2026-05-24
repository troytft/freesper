import SwiftUI

struct OnboardingStepChrome<Icon: View, Content: View>: View {
  @ViewBuilder var icon: () -> Icon
  let title: String
  let description: String
  @ViewBuilder var content: () -> Content

  private static var topInset: CGFloat { 128 }
  private static var horizontalInset: CGFloat { 24 }
  private static var iconHeight: CGFloat { 72 }

  var body: some View {
    VStack(spacing: 20) {
      icon()
        .frame(height: Self.iconHeight)

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
      .padding(.horizontal, Self.horizontalInset)

      content()

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, Self.topInset)
    .padding(.horizontal, Self.horizontalInset)
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
