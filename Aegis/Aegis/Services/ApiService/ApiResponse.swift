//
//  ApiResponse.swift
//  eltar-mobile
//
//  Created by Steve Agustinus on 21/03/26.
//

import Foundation
import SwiftUI


struct EmptyResponse: Codable {}

struct ApiError: Error {
    let error: String?
    let message: String?
    let status: Int

    init(error: String?, message: String?, status: Int = 0) {
        self.error = error
        self.message = message
        self.status = status
    }
}

struct ListResponse<T: Codable>: Codable {
    let list: T
    let page: Int?
    let perPage: Int?
    let total: Int?
    
    enum CodingKeys: String, CodingKey {
        case list
        case page
        case perPage = "per_page"
        case total
    }
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
struct LoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
    let requireDeviceRegistration: Bool?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
        case requireDeviceRegistration = "require_device_registration"
    }
}

struct DashboardData: Codable {
    let totalAttendance: Int
    let totalLate: Int
    let leaveTaken: Int
    let todayStatus: String
    let checkedInAt: Date?

    enum CodingKeys: String, CodingKey {
        case totalAttendance = "total_attendance"
        case totalLate = "total_late"
        case leaveTaken = "leave_taken"
        case todayStatus = "today_status"
        case checkedInAt = "check_in_at"
    }
}

struct AttendanceData: Codable {
    let date: String
    let checkedInAt: Date?
    let checkedOutAt: Date?
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case date
        case checkedInAt = "checked_in_at"
        case checkedOutAt = "checked_out_at"
        case status
    }
}
