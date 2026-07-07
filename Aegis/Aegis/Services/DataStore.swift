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
    var isRegistered: Bool = true

    var isLoading: Bool = false
    var errorMessage: String?
    
    var currentUser: User?
    var dashboardData: DashboardData?
    var attendanceHistoryData: [AttendanceData]?
    
    private let apiService: ApiServiceProtocol
    
    init(apiService: ApiServiceProtocol) {
        self.apiService = apiService
        
        self.isLoggedIn =
        UserDefaults.standard.string(forKey: "aegis-refresh-token") != nil &&
        UserDefaults.standard.string(forKey: "aegis-access-token") != nil
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
        
        // Save the token using the exact key required by HttpService
        UserDefaults.standard.set(response.refreshToken, forKey: "aegis-refresh-token")
        UserDefaults.standard.set(response.accessToken, forKey: "aegis-access-token")

        return response
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
