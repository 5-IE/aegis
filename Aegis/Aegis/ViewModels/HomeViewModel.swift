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
    @Published var todayStatus: TodayAttendanceStatus = .notCheckedIn
    @Published var attendanceHistory: [Attendance] = []
    
    // State Management
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    init() {
        self.setupTodayDate()
    }
    
    func requestData(dataStore: DataStore) async {
        if self.currentUser == nil {
            await self.fetchProfile(store: dataStore)
        }
        
        await self.fetchDashboardData(store: dataStore)
        await self.fetchAttendanceHistoryData(store: dataStore)
    }
    
    private func setupTodayDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy"
        self.todayLabel = formatter.string(from: Date())
    }
    
    func fetchProfile(store: DataStore) async {
        isLoading = true
        
        do {
            let profile = try await store.fetchProfile()
            currentUser = profile
        } catch let error as URLError where error.code == .cancelled {
            // Silently ignore cancellation errors
            print("Request was cancelled - this is expected behavior.")
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "Error") - \(error.message ?? "Something went wrong")"
        } catch {
            self.errorMessage = "An unexpected error occurred."
        }
        isLoading = false
    }
    
    func fetchDashboardData(store: DataStore) async {
        isLoading = true
        
        do {
            let dashboardData = try await store.fetchDashboard()
            self.totalAttendance = String(format: "%02d", dashboardData.totalAttendance)
            self.totalLate = String(format: "%02d", dashboardData.totalLate)
            self.leaveTaken = String(format: "%02d", dashboardData.leaveTaken)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let checkedInAt = dashboardData.checkedInAt {
                self.checkedInAt = formatter.string(from: checkedInAt)
            } else {
                self.checkedInAt = "-"
            }
            self.todayStatus = Self.mapTodayStatus(
                apiStatus: dashboardData.todayStatus,
                checkedInTime: self.checkedInAt
            )
        } catch let error as URLError where error.code == .cancelled {
            // Silently ignore cancellation errors
            print("Request was cancelled - this is expected behavior.")
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "Error") - \(error.message ?? "Something went wrong")"
        } catch {
            self.errorMessage = "An unexpected error occurred."
        }
        
        isLoading = false
    }
    
    func fetchAttendanceHistoryData(store: DataStore) async {
        isLoading = true
        
        do {
            let response = try await store.fetchAttendanceHistory()
            let attendanceHistoryData = response.list
            
            self.attendanceHistory = attendanceHistoryData
                .map { Attendance(from: $0) }
                .sorted { lhs, rhs in
                    Self.attendanceDate(from: lhs.date) > Self.attendanceDate(from: rhs.date)
                }
                .prefix(5)
                .map { $0 }
            
        } catch let error as URLError where error.code == .cancelled {
            // Silently ignore cancellation errors
            print("Request was cancelled - this is expected behavior.")
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "Error") - \(error.message ?? "Something went wrong")"
        } catch {
            print(error)
            self.errorMessage = "An unexpected error occurred."
        }
        
        isLoading = false
    }

    private static func attendanceDate(from value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value) ?? .distantPast
    }

    private static func mapTodayStatus(apiStatus: String, checkedInTime: String) -> TodayAttendanceStatus {
        switch apiStatus {
        case "Checked In":
            return .checkedIn(time: checkedInTime)
        case "Running Late":
            return .runningLate(time: checkedInTime)
        case "Not Checked In", "Off":
            return .notCheckedIn
        case "Checked Out", "Not Checked Out":
            return .checkedIn(time: checkedInTime)
        default:
            return .notCheckedIn
        }
    }
}
