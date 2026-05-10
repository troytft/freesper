import Foundation

enum ModelState {
  case notDownloaded
  case downloading(progress: Double)
  case ready
  case failed(Error)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }
}
