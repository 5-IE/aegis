import Foundation

enum AegisAPIError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case backend(code: String, message: String, statusCode: Int)
    case decoding(String)
    case network(String)
    case adminRequired
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The API base URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .backend(_, message, _):
            return message
        case let .decoding(message):
            return "Could not read the server response: \(message)"
        case let .network(message):
            return message
        case .adminRequired:
            return "Please sign in with an admin account."
        case .missingRefreshToken:
            return "Your session has expired. Please sign in again."
        }
    }
}

struct EmptyBody: Encodable {}

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct LogoutRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: APIUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct APIUser: Codable {
    let id: Int
    let username: String
    let role: String
    let session: String?
    let firstName: String?
    let lastName: String?
    let email: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case role
        case session
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    var sessionModel: UserSession {
        UserSession(
            id: id,
            username: username,
            role: role,
            session: session,
            firstName: firstName,
            lastName: lastName,
            email: email
        )
    }
}

struct BackendErrorResponse: Decodable {
    let error: String
    let message: String
}

struct FlexibleBool: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int != 0
        } else if let string = try? container.decode(String.self) {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) {
                self.value = true
            } else if ["false", "0", "no"].contains(normalized) {
                self.value = false
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected boolean-like value but found \(string)."
                )
            }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected Bool, Int, or String boolean value."
            )
        }
    }
}

struct AbsenceSummaryResponse: Decodable {
    let presentSummary: PresentSummary
    let absentSummary: AbsentSummary

    enum CodingKeys: String, CodingKey {
        case presentSummary = "present_summary"
        case absentSummary = "absent_summary"
    }

    struct PresentSummary: Decodable {
        let onTime: Int
        let lateClockIn: Int

        enum CodingKeys: String, CodingKey {
            case onTime = "on_time"
            case lateClockIn = "late_clock_in"
        }
    }

    struct AbsentSummary: Decodable {
        let absent: Int
        let noClockIn: Int

        enum CodingKeys: String, CodingKey {
            case absent
            case noClockIn = "no_clock_in"
        }
    }

    var model: DashboardSummary {
        DashboardSummary(
            onTime: presentSummary.onTime,
            lateClockIn: presentSummary.lateClockIn,
            absent: absentSummary.absent,
            noClockIn: absentSummary.noClockIn
        )
    }
}

struct OverviewResponse: Decodable {
    let list: [OverviewItem]
    let page: Int
    let perPage: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case list
        case page
        case perPage = "per_page"
        case total
    }
}

struct OverviewItem: Decodable {
    let name: String
    let session: String
    let clockedInAt: String?
    let clockedOutAt: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case name
        case session
        case clockedInAt = "clocked_in_at"
        case clockedOutAt = "clocked_out_at"
        case status
    }

    var model: AttendanceOverviewRow {
        AttendanceOverviewRow(
            name: name,
            session: session,
            clockedInAt: clockedInAt,
            clockedOutAt: clockedOutAt,
            status: status
        )
    }
}

struct RoomsResponse: Decodable {
    let list: [RoomItem]
}

struct RoomItem: Decodable {
    let id: Int
    let name: String

    var model: Room {
        Room(id: id, name: name)
    }
}

struct RoomMutationRequest: Encodable {
    let name: String
}

struct RoomMapResponse: Decodable {
    let list: [RoomMapItem]
}

struct RoomMapItem: Decodable {
    let id: Int
    let user: RoomUser
    let x: Double?
    let y: Double?

    var model: RadarPoint? {
        guard let x, let y else { return nil }
        return RadarPoint(
            id: id,
            userName: user.name,
            session: user.session,
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

struct RoomUser: Decodable {
    let id: Int
    let name: String
    let session: String?
}

struct CurrentOccupantsResponse: Decodable {
    let list: [CurrentOccupantItem]
}

struct CurrentOccupantItem: Decodable {
    let user: RoomUser
    let durationSeconds: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case user
        case durationSeconds = "duration_seconds"
        case status
    }

    var model: Occupant {
        Occupant(
            id: user.id,
            learner: user.name,
            session: user.session ?? "-",
            durationSeconds: durationSeconds,
            status: status
        )
    }
}

struct RoomAdditionalDataResponse: Decodable {
    let roomTemperature: Double
    let humidity: Double
    let peopleInRoom: Int

    enum CodingKeys: String, CodingKey {
        case roomTemperature = "room_temperature"
        case humidity
        case peopleInRoom = "people_in_room"
    }

    var model: RoomMetrics {
        RoomMetrics(temperature: roomTemperature, humidity: humidity, peopleInRoom: peopleInRoom)
    }
}

struct SessionConfigResponse: Decodable {
    let am: SessionConfigPayload
    let pm: SessionConfigPayload

    enum CodingKeys: String, CodingKey {
        case am = "AM"
        case pm = "PM"
    }

    var model: SessionConfigs {
        SessionConfigs(am: am.model, pm: pm.model)
    }
}

struct SessionConfigPayload: Codable {
    let startTime: String
    let lateAfter: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case lateAfter = "late_after"
        case endTime = "end_time"
    }

    var model: SessionConfig {
        SessionConfig(startTime: startTime, lateAfter: lateAfter, endTime: endTime)
    }

    init(model: SessionConfig) {
        self.startTime = model.startTime
        self.lateAfter = model.lateAfter
        self.endTime = model.endTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startTime = try container.decode(String.self, forKey: .startTime)
        self.lateAfter = try container.decode(String.self, forKey: .lateAfter)
        self.endTime = try container.decode(String.self, forKey: .endTime)
    }
}

struct SystemConfigResponse: Decodable {
    let presenceStalenessMinutes: Int
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case presenceStalenessMinutes = "presence_staleness_minutes"
        case timezone
    }

    var model: SystemConfig {
        SystemConfig(presenceStalenessMinutes: presenceStalenessMinutes, timezone: timezone)
    }
}

struct SystemConfigUpdateRequest: Encodable {
    let presenceStalenessMinutes: Int?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case presenceStalenessMinutes = "presence_staleness_minutes"
        case timezone
    }
}

struct AdminUsersResponse: Decodable {
    let list: [AdminUserPayload]
    let total: Int
    let page: Int
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case list
        case total
        case page
        case perPage = "per_page"
    }

    var model: AdminUsersPage {
        AdminUsersPage(
            users: list.map(\.model),
            total: total,
            page: page,
            perPage: perPage
        )
    }
}

struct AdminBeaconsResponse: Decodable {
    let list: [AdminBeaconPayload]
    let total: Int
    let page: Int
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case list
        case total
        case page
        case perPage = "per_page"
    }

    var model: AdminBeaconsPage {
        AdminBeaconsPage(
            beacons: list.map(\.model),
            total: total,
            page: page,
            perPage: perPage
        )
    }
}

struct AdminBeaconPayload: Decodable {
    let id: Int
    let name: String
    let beaconIdentifier: String
    let roomID: Int?
    let roomName: String?
    let positionX: Double?
    let positionY: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case beaconIdentifier = "beacon_identifier"
        case roomID = "room_id"
        case roomName = "room_name"
        case positionX = "position_x"
        case positionY = "position_y"
    }

    var model: AdminBeacon {
        AdminBeacon(
            id: id,
            name: name,
            beaconIdentifier: beaconIdentifier,
            roomID: roomID,
            roomName: roomName,
            positionX: positionX,
            positionY: positionY
        )
    }
}

struct AdminBeaconMutationRequest: Encodable {
    let name: String
    let beaconIdentifier: String
    let roomID: Int?
    let positionX: Double?
    let positionY: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case beaconIdentifier = "beacon_identifier"
        case roomID = "room_id"
        case positionX = "position_x"
        case positionY = "position_y"
    }

    /// The backend PATCH distinguishes absent (leave unchanged) from null
    /// (clear). This body always sends every key, encoding nil values as an
    /// explicit JSON null so an emptied field clears the stored value.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(beaconIdentifier, forKey: .beaconIdentifier)
        if let roomID {
            try container.encode(roomID, forKey: .roomID)
        } else {
            try container.encodeNil(forKey: .roomID)
        }
        if let positionX {
            try container.encode(positionX, forKey: .positionX)
        } else {
            try container.encodeNil(forKey: .positionX)
        }
        if let positionY {
            try container.encode(positionY, forKey: .positionY)
        } else {
            try container.encodeNil(forKey: .positionY)
        }
    }
}

struct AdminUserPayload: Decodable {
    let id: Int
    let username: String
    let email: String
    let role: String
    let session: String?
    let firstName: String?
    let lastName: String?
    let isActive: FlexibleBool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case role
        case session
        case firstName = "first_name"
        case lastName = "last_name"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    var model: AdminUser {
        AdminUser(
            id: id,
            username: username,
            email: email,
            role: AdminUserRole(rawValue: role) ?? .learner,
            session: session,
            firstName: firstName,
            lastName: lastName,
            isActive: isActive.value,
            createdAt: createdAt
        )
    }
}

struct AdminUserCreateRequest: Encodable {
    let username: String
    let password: String
    let email: String
    let role: String
    let session: String?
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case email
        case role
        case session
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct AdminUserUpdateRequest: Encodable {
    let email: String
    let role: String
    let session: String?
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case email
        case role
        case session
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct AdminPasswordResetRequest: Encodable {
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case newPassword = "new_password"
    }
}

struct RollupRequest: Encodable {
    let date: String?
    let userID: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case userID = "user_id"
    }
}

struct AttendanceReportResponse: Decodable {
    let range: Range
    let summary: Summary
    let perLearner: [Learner]
    let records: [Record]

    enum CodingKeys: String, CodingKey {
        case range
        case summary
        case perLearner = "per_learner"
        case records
    }

    struct Range: Decodable {
        let from: String
        let to: String
        let daysWithSessions: Int

        enum CodingKeys: String, CodingKey {
            case from
            case to
            case daysWithSessions = "days_with_sessions"
        }
    }

    struct Summary: Decodable {
        let learners: Int
        let attendanceRate: Double
        let totalLate: Int
        let totalAbsent: Int

        enum CodingKeys: String, CodingKey {
            case learners
            case attendanceRate = "attendance_rate"
            case totalLate = "total_late"
            case totalAbsent = "total_absent"
        }
    }

    struct Learner: Decodable {
        let userID: Int
        let name: String
        let session: String
        let present: Int
        let late: Int
        let absent: Int
        let attendanceRate: Double

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case name
            case session
            case present
            case late
            case absent
            case attendanceRate = "attendance_rate"
        }
    }

    struct Record: Decodable {
        let date: String
        let userID: Int
        let name: String
        let session: String
        let status: String
        let clockedInAt: String?
        let clockedOutAt: String?

        enum CodingKeys: String, CodingKey {
            case date
            case userID = "user_id"
            case name
            case session
            case status
            case clockedInAt = "clocked_in_at"
            case clockedOutAt = "clocked_out_at"
        }
    }

    var model: AttendanceReport {
        AttendanceReport(
            from: range.from,
            to: range.to,
            daysWithSessions: range.daysWithSessions,
            summary: AttendanceReportSummary(
                learners: summary.learners,
                attendanceRate: summary.attendanceRate,
                totalLate: summary.totalLate,
                totalAbsent: summary.totalAbsent
            ),
            perLearner: perLearner.map {
                AttendanceReportLearner(
                    userID: $0.userID,
                    name: $0.name,
                    session: $0.session,
                    present: $0.present,
                    late: $0.late,
                    absent: $0.absent,
                    attendanceRate: $0.attendanceRate
                )
            },
            records: records.map {
                AttendanceReportRecord(
                    date: $0.date,
                    userID: $0.userID,
                    name: $0.name,
                    session: $0.session,
                    status: $0.status,
                    clockedInAt: $0.clockedInAt,
                    clockedOutAt: $0.clockedOutAt
                )
            }
        )
    }
}

struct RollupResponse: Decodable {
    let processed: Int
    let skippedLeave: Int

    enum CodingKeys: String, CodingKey {
        case processed
        case skippedLeave = "skipped_leave"
    }

    var model: RollupResult {
        RollupResult(processed: processed, skippedLeave: skippedLeave)
    }
}

final class AegisAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL = AppEnvironment.current.resolvedBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        try await send(path: "/auth/login", method: "POST", body: LoginRequest(username: username, password: password))
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await send(path: "/auth/refresh", method: "POST", body: RefreshRequest(refreshToken: refreshToken))
    }

    func logout(refreshToken: String) async throws {
        let _: NoContent = try await send(path: "/auth/logout", method: "POST", body: LogoutRequest(refreshToken: refreshToken))
    }

    func getDashboardSummary(accessToken: String) async throws -> DashboardSummary {
        let response: AbsenceSummaryResponse = try await send(
            path: "/api/v1/admin/absence-summary",
            accessToken: accessToken
        )
        return response.model
    }

    func getOverview(
        accessToken: String,
        search: String,
        sessionFilter: SessionFilter,
        page: Int,
        perPage: Int
    ) async throws -> AttendanceOverviewPage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.append(URLQueryItem(name: "name", value: trimmed))
        }
        if let value = sessionFilter.queryValue {
            query.append(URLQueryItem(name: "session", value: value))
        }
        let response: OverviewResponse = try await send(
            path: "/api/v1/admin/overview",
            queryItems: query,
            accessToken: accessToken
        )
        return AttendanceOverviewPage(
            rows: response.list.map(\.model),
            total: response.total,
            page: response.page,
            perPage: response.perPage
        )
    }

    func getRooms(accessToken: String) async throws -> [Room] {
        let response: RoomsResponse = try await send(path: "/api/v1/admin/rooms", accessToken: accessToken)
        return response.list.map(\.model)
    }

    func createRoom(_ form: AdminRoomForm, accessToken: String) async throws -> Room {
        let request = RoomMutationRequest(name: form.name.trimmingCharacters(in: .whitespacesAndNewlines))
        let response: RoomItem = try await send(
            path: "/api/v1/admin/rooms",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
        return response.model
    }

    func updateRoom(id: Int, form: AdminRoomForm, accessToken: String) async throws -> Room {
        let request = RoomMutationRequest(name: form.name.trimmingCharacters(in: .whitespacesAndNewlines))
        let response: RoomItem = try await send(
            path: "/api/v1/admin/rooms/\(id)",
            method: "PATCH",
            body: request,
            accessToken: accessToken
        )
        return response.model
    }

    func deleteRoom(id: Int, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/rooms/\(id)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func getRoomMap(roomID: Int, accessToken: String) async throws -> [RadarPoint] {
        let response: RoomMapResponse = try await send(path: "/api/v1/admin/rooms/\(roomID)/map", accessToken: accessToken)
        return response.list.compactMap(\.model)
    }

    func getCurrentOccupants(roomID: Int, accessToken: String) async throws -> [Occupant] {
        let response: CurrentOccupantsResponse = try await send(path: "/api/v1/admin/rooms/\(roomID)/current-occupants", accessToken: accessToken)
        return response.list.map(\.model)
    }

    func getRoomMetrics(roomID: Int, accessToken: String) async throws -> RoomMetrics {
        let response: RoomAdditionalDataResponse = try await send(path: "/api/v1/admin/rooms/\(roomID)/additional-data", accessToken: accessToken)
        return response.model
    }

    func getSessionConfig(accessToken: String) async throws -> SessionConfigs {
        let response: SessionConfigResponse = try await send(path: "/api/v1/admin/session-config", accessToken: accessToken)
        return response.model
    }

    func updateSessionConfig(session: String, config: SessionConfig, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/session-config/\(session)",
            method: "PUT",
            body: SessionConfigPayload(model: config),
            accessToken: accessToken
        )
    }

    func getSystemConfig(accessToken: String) async throws -> SystemConfig {
        let response: SystemConfigResponse = try await send(path: "/api/v1/admin/system-config", accessToken: accessToken)
        return response.model
    }

    func updateSystemConfig(_ config: SystemConfig, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/system-config",
            method: "PUT",
            body: SystemConfigUpdateRequest(
                presenceStalenessMinutes: config.presenceStalenessMinutes,
                timezone: config.timezone
            ),
            accessToken: accessToken
        )
    }

    func getAdminUsers(
        accessToken: String,
        search: String,
        roleFilter: AdminUserRoleFilter,
        sessionFilter: SessionFilter,
        includeInactive: Bool,
        page: Int,
        perPage: Int
    ) async throws -> AdminUsersPage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "include_inactive", value: includeInactive ? "true" : "false")
        ]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.append(URLQueryItem(name: "name", value: trimmed))
        }
        if let role = roleFilter.queryValue {
            query.append(URLQueryItem(name: "role", value: role))
        }
        if let session = sessionFilter.queryValue {
            query.append(URLQueryItem(name: "session", value: session))
        }
        let response: AdminUsersResponse = try await send(
            path: "/api/v1/admin/users",
            queryItems: query,
            accessToken: accessToken
        )
        return response.model
    }

    func createAdminUser(_ form: AdminUserForm, accessToken: String) async throws -> AdminUser {
        let request = AdminUserCreateRequest(
            username: form.username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: form.password,
            email: form.email.trimmingCharacters(in: .whitespacesAndNewlines),
            role: form.role.rawValue,
            session: form.role == .learner ? form.session : nil,
            firstName: cleanOptional(form.firstName),
            lastName: cleanOptional(form.lastName)
        )
        let response: AdminUserPayload = try await send(
            path: "/api/v1/admin/users",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
        return response.model
    }

    func updateAdminUser(id: Int, form: AdminUserForm, accessToken: String) async throws -> AdminUser {
        let request = AdminUserUpdateRequest(
            email: form.email.trimmingCharacters(in: .whitespacesAndNewlines),
            role: form.role.rawValue,
            session: form.role == .learner ? form.session : nil,
            firstName: cleanOptional(form.firstName),
            lastName: cleanOptional(form.lastName)
        )
        let response: AdminUserPayload = try await send(
            path: "/api/v1/admin/users/\(id)",
            method: "PATCH",
            body: request,
            accessToken: accessToken
        )
        return response.model
    }

    func resetAdminUserPassword(id: Int, newPassword: String, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/users/\(id)/password",
            method: "PUT",
            body: AdminPasswordResetRequest(newPassword: newPassword),
            accessToken: accessToken
        )
    }

    func deleteAdminUser(id: Int, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/users/\(id)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func reactivateAdminUser(id: Int, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/users/\(id)/reactivate",
            method: "POST",
            accessToken: accessToken
        )
    }

    func getAdminBeacons(
        accessToken: String,
        assignmentFilter: BeaconAssignmentFilter,
        roomID: Int?,
        page: Int,
        perPage: Int
    ) async throws -> AdminBeaconsPage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        if let assigned = assignmentFilter.queryValue {
            query.append(URLQueryItem(name: "assigned", value: assigned ? "true" : "false"))
        }
        if let roomID {
            query.append(URLQueryItem(name: "room_id", value: "\(roomID)"))
        }
        let response: AdminBeaconsResponse = try await send(
            path: "/api/v1/admin/beacons",
            queryItems: query,
            accessToken: accessToken
        )
        return response.model
    }

    func createAdminBeacon(_ form: AdminBeaconForm, accessToken: String) async throws -> AdminBeacon {
        let request = AdminBeaconMutationRequest(
            name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            beaconIdentifier: form.beaconIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            roomID: form.roomID,
            positionX: form.positionXValue,
            positionY: form.positionYValue
        )
        let response: AdminBeaconPayload = try await send(
            path: "/api/v1/admin/beacons",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
        return response.model
    }

    func updateAdminBeacon(id: Int, form: AdminBeaconForm, accessToken: String) async throws -> AdminBeacon {
        let request = AdminBeaconMutationRequest(
            name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            beaconIdentifier: form.beaconIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            roomID: form.roomID,
            positionX: form.positionXValue,
            positionY: form.positionYValue
        )
        let response: AdminBeaconPayload = try await send(
            path: "/api/v1/admin/beacons/\(id)",
            method: "PATCH",
            body: request,
            accessToken: accessToken
        )
        return response.model
    }

    func deleteAdminBeacon(id: Int, accessToken: String) async throws {
        let _: NoContent = try await send(
            path: "/api/v1/admin/beacons/\(id)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func getAttendanceReport(
        from: String,
        to: String,
        session: SessionFilter,
        accessToken: String
    ) async throws -> AttendanceReport {
        let response: AttendanceReportResponse = try await send(
            path: "/api/v1/admin/reports/attendance",
            queryItems: attendanceReportQuery(from: from, to: to, session: session),
            accessToken: accessToken
        )
        return response.model
    }

    func downloadAttendanceReportCSV(
        from: String,
        to: String,
        session: SessionFilter,
        accessToken: String
    ) async throws -> Data {
        var query = attendanceReportQuery(from: from, to: to, session: session)
        query.append(URLQueryItem(name: "format", value: "csv"))
        do {
            let request = try makeRequest(
                path: "/api/v1/admin/reports/attendance",
                method: "GET",
                queryItems: query,
                body: Optional<EmptyBody>.none,
                accessToken: accessToken
            )
            // `self.session`: the `session` parameter (a SessionFilter)
            // shadows the URLSession property here.
            let (data, response) = try await self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AegisAPIError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                if let backend = try? decoder.decode(BackendErrorResponse.self, from: data) {
                    throw AegisAPIError.backend(code: backend.error, message: backend.message, statusCode: http.statusCode)
                }
                throw AegisAPIError.backend(
                    code: "http_\(http.statusCode)",
                    message: "Request failed with status \(http.statusCode).",
                    statusCode: http.statusCode
                )
            }
            return data
        } catch let error as AegisAPIError {
            throw error
        } catch {
            throw AegisAPIError.network(error.localizedDescription)
        }
    }

    private func attendanceReportQuery(from: String, to: String, session: SessionFilter) -> [URLQueryItem] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        if let value = session.queryValue {
            query.append(URLQueryItem(name: "session", value: value))
        }
        return query
    }

    func runRollup(date: String?, userID: Int?, accessToken: String) async throws -> RollupResult {
        let response: RollupResponse = try await send(
            path: "/api/v1/admin/rollup",
            method: "POST",
            body: RollupRequest(date: date, userID: userID),
            accessToken: accessToken
        )
        return response.model
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body? = nil,
        accessToken: String? = nil
    ) async throws -> Response {
        do {
            let request = try makeRequest(path: path, method: method, queryItems: queryItems, body: body, accessToken: accessToken)
            let (data, response) = try await session.data(for: request)
            return try decodeResponse(data: data, response: response)
        } catch let error as AegisAPIError {
            throw error
        } catch let error as DecodingError {
            throw AegisAPIError.decoding(Self.describe(error))
        } catch {
            throw AegisAPIError.network(error.localizedDescription)
        }
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            body: Optional<EmptyBody>.none,
            accessToken: accessToken
        )
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Body?,
        accessToken: String?
    ) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL.appendingPathComponent(normalizedPath), resolvingAgainstBaseURL: false) else {
            throw AegisAPIError.invalidBaseURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw AegisAPIError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func decodeResponse<Response: Decodable>(data: Data, response: URLResponse) throws -> Response {
        guard let http = response as? HTTPURLResponse else {
            throw AegisAPIError.invalidResponse
        }
        if http.statusCode == 204 {
            if Response.self == NoContent.self {
                return NoContent() as! Response
            }
            throw AegisAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let backend = try? decoder.decode(BackendErrorResponse.self, from: data) {
                throw AegisAPIError.backend(code: backend.error, message: backend.message, statusCode: http.statusCode)
            }
            throw AegisAPIError.backend(code: "http_\(http.statusCode)", message: "Request failed with status \(http.statusCode).", statusCode: http.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func cleanOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "Missing field '\(key.stringValue)' at \(codingPath(context.codingPath))."
        case let .typeMismatch(type, context):
            return "Field \(codingPath(context.codingPath)) has the wrong type. Expected \(type)."
        case let .valueNotFound(type, context):
            return "Field \(codingPath(context.codingPath)) was empty. Expected \(type)."
        case let .dataCorrupted(context):
            return "Invalid value at \(codingPath(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "response root" }
        return path.map(\.stringValue).joined(separator: ".")
    }
}

struct NoContent: Decodable {}
