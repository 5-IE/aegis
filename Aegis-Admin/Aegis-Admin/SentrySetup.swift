import Foundation
import Sentry

enum SentrySetup {
    static func start() {
        SentrySDK.start { options in
            options.dsn = "https://dd39e6b3d46b0b4f807461d7215c0fcf@o4511703799824384.ingest.us.sentry.io/4511703844061184"
            options.tracesSampleRate = 0.2
            options.enableAutoSessionTracking = true
            options.attachScreenshot = true
            options.environment = AppEnvironment.current == .production ? "production" : "development"
        }
    }
}
