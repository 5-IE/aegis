//
//  AttendanceHistoryViewModel.swift
//  Aegis
//
//  Created by Felicia Audy on 07/07/26.
//

import Foundation
import Combine

struct AttendanceMonthOption: Identifiable, Equatable {
    let label: String
    let month: Int
    let year: Int

    var id: String {
        "\(year)-\(month)"
    }
}

@MainActor
class AttendanceHistoryViewModel: ObservableObject {
    @Published var attendanceHistory: [Attendance] = []
    @Published var availableMonths: [AttendanceMonthOption] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func fetchAvailableMonths(store: DataStore) async {
 //       MARK: - Mock Data
//        self.availableMonths = Self.mockAvailableMonths()
//        return

        do {
            let response = try await store.fetchAttendanceHistory()
            let mappedHistory = response.list.map { Attendance(from: $0) }
            self.availableMonths = Self.monthOptions(from: mappedHistory)
        } catch {
            self.availableMonths = []
        }
    }

    func fetchAttendanceHistoryData(store: DataStore, month: Int, year: Int) async {
        isLoading = true
        errorMessage = nil

        // MARK: - Mock Data
//        self.attendanceHistory = Self.mockAttendanceHistory(month: month, year: year)
//        isLoading = false
//        return
//        
        do {
            let response = try await store.fetchAttendanceHistory(month: month, year: year)
            let attendanceHistoryData = response.list
            
            let mappedHistory = attendanceHistoryData.map { Attendance(from: $0) }
            self.attendanceHistory = Self.history(mappedHistory, matchesMonth: month, year: year)
                ? mappedHistory
                : []
            
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "") - \(error.message ?? "")"
            self.attendanceHistory = []
        } catch {
            self.errorMessage = "An unexpected error occurred."
            self.attendanceHistory = []
        }
        
        isLoading = false
    }

    func hasAttendanceHistory(month: Int, year: Int) -> Bool {
        availableMonths.contains { $0.month == month && $0.year == year }
    }

    private static func history(_ history: [Attendance], matchesMonth month: Int, year: Int) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return history.contains { attendance in
            guard let date = formatter.date(from: attendance.date) else { return false }
            let components = Calendar.current.dateComponents([.month, .year], from: date)
            return components.month == month && components.year == year
        }
    }

    private static func monthOptions(from history: [Attendance]) -> [AttendanceMonthOption] {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMMM yyyy"
        displayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let uniqueDates = Set(history.compactMap { attendance -> Date? in
            guard let date = formatter.date(from: attendance.date) else { return nil }
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            return Calendar.current.date(from: components)
        })

        return uniqueDates
            .sorted()
            .compactMap { date in
                let components = Calendar.current.dateComponents([.month, .year], from: date)
                guard let month = components.month, let year = components.year else { return nil }
                return AttendanceMonthOption(label: displayFormatter.string(from: date), month: month, year: year)
            }
    }

    private static func mockAvailableMonths() -> [AttendanceMonthOption] {
        [
            AttendanceMonthOption(label: "May 2026", month: 5, year: 2026),
            AttendanceMonthOption(label: "June 2026", month: 6, year: 2026),
            AttendanceMonthOption(label: "July 2026", month: 7, year: 2026)
        ]
    }

    private static func mockAttendanceHistory(month: Int, year: Int) -> [Attendance] {
        switch (month, year) {
        case (5, 2026):
            return [
                Attendance(date: "Fri, 29 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:03 AM - 05:01 PM", status: .onTime),
                Attendance(date: "Thu, 28 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:31 AM - 05:08 PM", status: .late),
                Attendance(date: "Wed, 27 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "-", status: .leave),
                Attendance(date: "Tue, 26 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "07:55 AM - 05:00 PM", status: .onTime)
            ]
        case (6, 2026):
            return [
                Attendance(date: "Fri, 26 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:00 AM - 05:05 PM", status: .onTime),
                Attendance(date: "Thu, 25 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:14 AM - 05:10 PM", status: .onTime),
                Attendance(date: "Wed, 24 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:28 AM - 05:03 PM", status: .late),
                Attendance(date: "Tue, 23 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "07:58 AM - 05:00 PM", status: .onTime)
            ]
        case (7, 2026):
            return [
                Attendance(date: "Wed, 9 Jul 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "-", status: .leave),
                Attendance(date: "Tue, 8 Jul 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:25 AM - 05:10 PM", status: .late),
                Attendance(date: "Mon, 7 Jul 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:00 AM - 05:05 PM", status: .onTime)
            ]
        default:
            return []
        }
    }
}
