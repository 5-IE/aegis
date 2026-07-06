import Combine
import Foundation
import Security

final class KeychainStore {
    private let service = "ada.Aegis-Admin"

    func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw AegisAPIError.network("Could not save credentials.")
            }
        } else if status != errSecSuccess {
            throw AegisAPIError.network("Could not update credentials.")
        }
    }

    func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AegisAPIError.network("Could not read credentials.")
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(UserSession)
    }

    @Published private(set) var state: State = .restoring
    @Published private(set) var authError: String?

    private let api: AegisAPIClient
    private let keychain: KeychainStore
    private let userEncoder = JSONEncoder()
    private let userDecoder = JSONDecoder()
    private var accessToken: String?
    private var refreshToken: String?

    private enum KeychainKey {
        static let refreshToken = "refresh_token"
        static let user = "admin_user"
    }

    init() {
        self.api = AegisAPIClient()
        self.keychain = KeychainStore()
    }

    init(api: AegisAPIClient, keychain: KeychainStore) {
        self.api = api
        self.keychain = keychain
    }

    var currentUser: UserSession? {
        if case let .signedIn(user) = state {
            return user
        }
        return nil
    }

    func restoreSession() async {
        do {
            guard let storedRefreshToken = try keychain.get(KeychainKey.refreshToken) else {
                state = .signedOut
                return
            }
            let response = try await api.refresh(refreshToken: storedRefreshToken)
            accessToken = response.accessToken
            refreshToken = response.refreshToken
            try keychain.set(response.refreshToken, for: KeychainKey.refreshToken)

            if let user = try loadStoredUser() {
                state = .signedIn(user)
            } else {
                signOutLocally()
            }
        } catch {
            signOutLocally()
        }
    }

    func signIn(username: String, password: String) async {
        authError = nil
        do {
            let response = try await api.login(username: username, password: password)
            guard let apiUser = response.user, apiUser.role == "admin" else {
                throw AegisAPIError.adminRequired
            }
            let user = apiUser.sessionModel
            accessToken = response.accessToken
            refreshToken = response.refreshToken
            try keychain.set(response.refreshToken, for: KeychainKey.refreshToken)
            try saveUser(user)
            state = .signedIn(user)
        } catch {
            authError = readableMessage(for: error)
        }
    }

    func signOut() async {
        if let refreshToken {
            try? await api.logout(refreshToken: refreshToken)
        }
        signOutLocally()
    }

    func authorized<T>(_ operation: (String) async throws -> T) async throws -> T {
        guard let accessToken else {
            throw AegisAPIError.missingRefreshToken
        }
        do {
            return try await operation(accessToken)
        } catch let error as AegisAPIError {
            if error.isUnauthorized {
                return try await refreshAndRetry(operation)
            }
            throw error
        }
    }

    func dashboardSummary() async throws -> DashboardSummary {
        try await authorized { token in
            try await api.getDashboardSummary(accessToken: token)
        }
    }

    func overview(search: String, sessionFilter: SessionFilter) async throws -> [AttendanceOverviewRow] {
        try await authorized { token in
            try await api.getOverview(accessToken: token, search: search, sessionFilter: sessionFilter)
        }
    }

    func rooms() async throws -> [Room] {
        try await authorized { token in
            try await api.getRooms(accessToken: token)
        }
    }

    func roomMap(roomID: Int) async throws -> [RadarPoint] {
        try await authorized { token in
            try await api.getRoomMap(roomID: roomID, accessToken: token)
        }
    }

    func currentOccupants(roomID: Int) async throws -> [Occupant] {
        try await authorized { token in
            try await api.getCurrentOccupants(roomID: roomID, accessToken: token)
        }
    }

    func roomMetrics(roomID: Int) async throws -> RoomMetrics {
        try await authorized { token in
            try await api.getRoomMetrics(roomID: roomID, accessToken: token)
        }
    }

    func sessionConfigs() async throws -> SessionConfigs {
        try await authorized { token in
            try await api.getSessionConfig(accessToken: token)
        }
    }

    func updateSessionConfig(session: String, config: SessionConfig) async throws {
        try await authorized { token in
            try await api.updateSessionConfig(session: session, config: config, accessToken: token)
        }
    }

    func systemConfig() async throws -> SystemConfig {
        try await authorized { token in
            try await api.getSystemConfig(accessToken: token)
        }
    }

    func updateSystemConfig(_ config: SystemConfig) async throws {
        try await authorized { token in
            try await api.updateSystemConfig(config, accessToken: token)
        }
    }

    private func refreshAndRetry<T>(_ operation: (String) async throws -> T) async throws -> T {
        guard let refreshToken else {
            throw AegisAPIError.missingRefreshToken
        }
        let response = try await api.refresh(refreshToken: refreshToken)
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        try keychain.set(response.refreshToken, for: KeychainKey.refreshToken)
        return try await operation(response.accessToken)
    }

    private func saveUser(_ user: UserSession) throws {
        let data = try userEncoder.encode(user)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw AegisAPIError.decoding("Could not encode user metadata.")
        }
        try keychain.set(encoded, for: KeychainKey.user)
    }

    private func loadStoredUser() throws -> UserSession? {
        guard let encoded = try keychain.get(KeychainKey.user),
              let data = encoded.data(using: .utf8) else {
            return nil
        }
        return try userDecoder.decode(UserSession.self, from: data)
    }

    private func signOutLocally() {
        accessToken = nil
        refreshToken = nil
        keychain.delete(KeychainKey.refreshToken)
        keychain.delete(KeychainKey.user)
        state = .signedOut
    }

    private func readableMessage(for error: Error) -> String {
        if let apiError = error as? AegisAPIError {
            return apiError.localizedDescription
        }
        return error.localizedDescription
    }
}

private extension AegisAPIError {
    var isUnauthorized: Bool {
        if case let .backend(code, _, statusCode) = self {
            return statusCode == 401 || code == "unauthorized" || code == "invalid_grant"
        }
        return false
    }
}
