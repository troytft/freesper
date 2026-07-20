import Foundation
import OSLog
import Sentry

enum CrashReporting {
  static func startIfConfigured(log: Logger) {
    guard
      let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
      !dsn.isEmpty
    else {
      log.info("Crash reporting disabled: no DSN configured")
      return
    }
    SentrySDK.start { options in
      options.dsn = dsn
      options.sendDefaultPii = false
      #if DEBUG
        options.environment = "debug"
      #endif
    }
    log.info("Crash reporting enabled")
  }
}
