//
//  HomeViewModel.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//


import Foundation
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var todayLabel: String = ""
    
    // Data
    @Published var currentUser: User?
    @Published var totalAttendance: String = "00"
    @Published var totalLate: String = "00"
    @Published var leaveTaken: String = "00"
    @Published var checkedInAt: String = ""
    @Published var attendanceHistory: [Attendance] = []
    
    // State Management
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    init() {
        self.setupTodayDate()
    }
    
    private func setupTodayDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy"
        self.todayLabel = formatter.string(from: Date())
    }
    
    func fetchProfile(store: DataStore) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let profile = try await store.fetchProfile()
            currentUser = profile
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "") - \(error.message ?? "")"
        } catch {
            self.errorMessage = "An unexpected error occurred."
        }
        isLoading = false
    }
    
    func fetchDashboardData(store: DataStore) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let dashboardData = try await store.fetchDashboard()
            self.totalAttendance = String(format: "%02d", dashboardData.totalAttendance)
            self.totalLate = String(format: "%02d", dashboardData.totalLate)
            self.leaveTaken = String(format: "%02d", dashboardData.leaveTaken)
            
            
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let checkedInAt = dashboardData.checkedInAt {
                self.checkedInAt = "\(formatter.string(from: checkedInAt))"
            } else {
                self.checkedInAt = "-"
            }
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "") - \(error.message ?? "")"
        } catch {
            self.errorMessage = "An unexpected error occurred."
        }
        
        isLoading = false
    }
    
    func fetchAttendanceHistoryData(store: DataStore) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await store.fetchAttendanceHistory()
            let attendanceHistoryData = response.list
            
            self.attendanceHistory = attendanceHistoryData.map { Attendance(from: $0) }
            
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "") - \(error.message ?? "")"
        } catch {
            self.errorMessage = "An unexpected error occurred."
        }
        
        isLoading = false
    }
}
