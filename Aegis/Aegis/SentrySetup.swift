import Foundation
import Sentry

enum SentrySetup {
    static func start() {
        SentrySDK.start { options in
            options.dsn = "https://ff19bbf999de5806c8a5e2e5afcaccbc@o4511703799824384.ingest.us.sentry.io/4511703840522240"
            options.tracesSampleRate = 0.2
            options.enableAutoSessionTracking = true
            options.attachScreenshot = true
            options.environment = AppEnvironment.current == .production ? "production" : "development"
        }
    }
}
