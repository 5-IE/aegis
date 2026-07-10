//
//  ApiService.swift
//  eltar-mobile
//
//  Created by Steve Agustinus on 21/03/26.
//

protocol ApiServiceProtocol {
    func login(username: String, password: String) async throws -> LoginResponse
    func refreshToken(refreshToken: String) async throws -> AuthResponse
    func registerDevice(publicKey: String) async throws -> EmptyResponse
    func sendPresence(roomId: Int, positionX: Double?, positionY: Double?, batteryLevel: Int?) async throws -> EmptyResponse
    func fetchProfile() async throws -> User
    func fetchDashboard() async throws -> DashboardData
    func fetchAttendanceHistory(month: Int?, year: Int?, page: Int?, perPage: Int?) async throws -> ListResponse<[AttendanceData]>
    func fetchBeacons() async throws -> ListResponse<[BeaconData]>
}

extension ApiServiceProtocol {
    func fetchAttendanceHistory(month: Int? = nil, year: Int? = nil, page: Int? = nil, perPage: Int? = nil) async throws -> ListResponse<[AttendanceData]> {
        return try await fetchAttendanceHistory(month: month, year: year, page: page, perPage: perPage)
    }
}

class ApiService: HttpService, ApiServiceProtocol {
    
    func login(username: String, password: String) async throws -> LoginResponse {
        let params = ["username": username, "password": password]
        return try await request("POST", endpoint: "/auth/login", params: params)
    }
    func refreshToken(refreshToken: String) async throws -> AuthResponse {
        let params = ["refresh_token": refreshToken]
        return try await request("POST", endpoint: "/auth/refresh", params: params)
    }
    func registerDevice(publicKey: String) async throws -> EmptyResponse {
        let params = ["device_public_key": publicKey]
        return try await request("POST", endpoint: "/api/v1/register-device", params: params)
    }
    func sendPresence(roomId: Int, positionX: Double? = nil, positionY: Double? = nil, batteryLevel: Int? = nil) async throws -> EmptyResponse {
        var params: [String: Any] = ["room_id": roomId]
        if let positionX { params["position_x"] = positionX }
        if let positionY { params["position_y"] = positionY }
        if let batteryLevel { params["battery_level"] = batteryLevel }
        return try await request("POST", endpoint: "/api/v1/presence", params: params)
    }
    func fetchProfile() async throws -> User {
        return try await request("GET", endpoint: "/api/v1/me")
    }
    func fetchDashboard() async throws -> DashboardData {
        return try await request("GET", endpoint: "/api/v1/dashboard")
    }
    func fetchBeacons() async throws -> ListResponse<[BeaconData]> {
        return try await request("GET", endpoint: "/api/v1/beacons")
    }
    func fetchAttendanceHistory(month: Int?, year: Int?, page: Int?, perPage: Int?) async throws -> ListResponse<[AttendanceData]> {
        var params: [String: String] = [:]
        if let month { params["month"] = String(month) }
        if let year { params["year"] = String(year) }
        if let page { params["page"] = String(page) }
        if let perPage { params["per_page"] = String(perPage) }
        return try await request("GET", endpoint: "/api/v1/histories", queryParams: params)
    }
}
