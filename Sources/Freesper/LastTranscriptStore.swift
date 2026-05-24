import Foundation

@MainActor
@Observable
final class LastTranscriptStore {
  private(set) var text: String?
  /// Incremented on every `record(_:)`. Observers that need to react to
  /// each delivery (not just to *changes* in the text) should watch this.
  private(set) var version: Int = 0

  func record(_ text: String) {
    self.text = text
    version += 1
  }
}
