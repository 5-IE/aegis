import Foundation

/// Environment-aware API endpoint configuration, mirroring
/// Aegis/Aegis/AppConfig/AppEnvironment.swift in the learner app.
enum AppEnvironment {
    case development
    case production

    static let current: AppEnvironment = .development

    /// Compiled-in defaults, used when no override is provided.
    private var defaultBaseURL: String {
        switch self {
        case .development:
            return "http://10.64.58.125:3000"
        case .production:
            return "http://10.64.58.125:3000"
        }
    }

    /// Base URL for the API.
    ///
    /// Resolution order (first non-empty wins):
    ///   1. `AEGIS_BASE_URL` process environment variable (set it in the Xcode
    ///      scheme's Run → Arguments → Environment Variables for local dev).
    ///   2. `AEGIS_BASE_URL` key in Info.plist (drive it from an .xcconfig /
    ///      build setting for per-configuration values).
    ///   3. The compiled-in default above.
    var baseURL: String {
        if let env = ProcessInfo.processInfo.environment["AEGIS_BASE_URL"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "AEGIS_BASE_URL") as? String,
           !plist.trimmingCharacters(in: .whitespaces).isEmpty {
            return plist
        }
        return defaultBaseURL
    }

    /// The resolved base URL, failing loudly (with the offending string) when
    /// the configured value cannot be parsed as a URL.
    var resolvedBaseURL: URL {
        let raw = baseURL
        guard let url = URL(string: raw), url.scheme != nil, url.host != nil else {
            preconditionFailure("AEGIS_BASE_URL is not a valid absolute URL: '\(raw)'")
        }
        return url
    }
}
