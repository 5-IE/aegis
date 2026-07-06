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

final class AegisAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL = URL(string: "http://localhost:3000")!, session: URLSession = .shared) {
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

    func getOverview(accessToken: String, search: String, sessionFilter: SessionFilter) async throws -> [AttendanceOverviewRow] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "100")
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
        return response.list.map(\.model)
    }

    func getRooms(accessToken: String) async throws -> [Room] {
        let response: RoomsResponse = try await send(path: "/api/v1/admin/rooms", accessToken: accessToken)
        return response.list.map(\.model)
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
            throw AegisAPIError.decoding(error.localizedDescription)
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
}

struct NoContent: Decodable {}
