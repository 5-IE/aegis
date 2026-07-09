//
//  DataStore.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//


import Foundation
import Observation
import Combine
import SwiftUI

@Observable
@MainActor
class DataStore {
    // Global States
    var isLoggedIn: Bool = false
    var isRegistered: Bool = UserDefaults.standard.bool(forKey: "aegis-device-registered")

    var isLoading: Bool = false
    var errorMessage: String?
    
    var currentUser: User?
    var dashboardData: DashboardData?
    var attendanceHistoryData: [AttendanceData]?
    var beacons: [Beacon]?
    
    private let apiService: ApiServiceProtocol
    
    init(apiService: ApiServiceProtocol) {
        self.apiService = apiService
        
        self.isLoggedIn =
        UserDefaults.standard.string(forKey: "aegis-refresh-token") != nil &&
        UserDefaults.standard.string(forKey: "aegis-access-token") != nil
        
        self.isRegistered = UserDefaults.standard.bool(forKey: "aegis-is-registered")
    }
    
    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        
//        do {
//            // Fetch everything concurrently
////
//        } catch {
//            self.errorMessage = "Failed to sync data: \(error.localizedDescription)"
//        }
        
        isLoading = false
    }
    
    func login(username: String, password: String) async throws -> LoginResponse {
        let response = try await apiService.login(username: username, password: password)
        self.currentUser = response.user

        UserDefaults.standard.set(response.refreshToken, forKey: "aegis-refresh-token")
        UserDefaults.standard.set(response.accessToken, forKey: "aegis-access-token")

        let registered = !(response.requireDeviceRegistration ?? false)
        self.isRegistered = registered
        UserDefaults.standard.set(registered, forKey: "aegis-device-registered")

        return response
    }
    
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "aegis-access-token")
        UserDefaults.standard.removeObject(forKey: "aegis-refresh-token")
        currentUser = nil
        dashboardData = nil
        attendanceHistoryData = nil
        isLoggedIn = false
    }

    func fetchProfile() async throws -> User {
        let profile = try await apiService.fetchProfile()
        self.currentUser = profile
        return profile
    }
    
    func fetchDashboard() async throws -> DashboardData {
        let dashboardData = try await apiService.fetchDashboard()
        self.dashboardData = dashboardData
        return dashboardData
    }
    
    func fetchAttendanceHistory() async throws -> ListResponse<[AttendanceData]> {
        let attendanceHistoryData = try await apiService.fetchAttendanceHistory()
        self.attendanceHistoryData = attendanceHistoryData.list
        return attendanceHistoryData
    }
    
    func fetchAttendanceHistory(month: Int, year: Int) async throws -> ListResponse<[AttendanceData]> {
        let attendanceHistoryData = try await apiService.fetchAttendanceHistory(month: month, year: year)
        self.attendanceHistoryData = attendanceHistoryData.list
        return attendanceHistoryData
    }
    
    func fetchBeacons() async throws -> ListResponse<[Beacon]> {
        let response = try await apiService.fetchBeacons()
        self.beacons = response.list
        return response
    }

    func registerDevice(publicKey: String) async throws -> EmptyResponse {
        let response = try await apiService.registerDevice(publicKey: publicKey)
        
        // Save the token using the exact key required by HttpService
        UserDefaults.standard.set(true, forKey: "aegis-is-registered")

        return response
    }
    
    
//    func addTransaction(_ transaction: Transaction) async throws {
//        try await apiService.addTransaction(transaction)
//        
//        // Optimistically add to the local source of truth
//        transactions.append(transaction)
//        // Optionally re-sort if you want the store to enforce an order
//        transactions.sort { $0.date > $1.date }
//    }
//    
//    func deleteTransaction(_ id: UUID) async throws {
//        try await apiService.deleteTransaction(id: id)
//        
//        // Optimistically remove from the local source of truth
//        transactions.removeAll { $0.id == id }
//    }
}
