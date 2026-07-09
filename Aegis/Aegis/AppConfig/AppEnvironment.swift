//
//  AppEnvironment.swift
//  Aegis
//
//  Created by Steve Agustinus on 03/07/26.
//


import Foundation

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
}
