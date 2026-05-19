import SwiftUI

struct AboutView: View {
  private let repositoryURL = URL(string: "https://github.com/troytft/freesper")!
  private let issuesURL = URL(string: "https://github.com/troytft/freesper/issues/new")!
  private let fluidAudioURL = URL(string: "https://github.com/FluidInference/FluidAudio")!

  var body: some View {
    VStack(spacing: 16) {
      Image("AppIcon")
        .resizable()
        .frame(width: 96, height: 96)
      VStack(spacing: 4) {
        Text("Freesper")
          .font(.title.weight(.semibold))
        Text(version)
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 16) {
        Link("View on GitHub", destination: repositoryURL)
        Link("Report an Issue", destination: issuesURL)
      }
      VStack(spacing: 2) {
        Text("Open source under the Apache 2.0 license.")
        HStack(spacing: 4) {
          Text("Speech recognition by")
          Link("FluidAudio", destination: fluidAudioURL)
        }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var version: String {
    "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String)"
  }
}
