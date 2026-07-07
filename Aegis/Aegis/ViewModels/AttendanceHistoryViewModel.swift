//
//  AttendanceHistoryViewModel.swift
//  Aegis
//
//  Created by Felicia Audy on 07/07/26.
//

import Foundation
import Combine

@MainActor
class AttendanceHistoryViewModel: ObservableObject {
    @Published var attendanceHistory: [Attendance] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

//    init() {
//        self.attendanceHistory = Self.mockAttendanceHistory(month: 6, year: 2026)
//    }

    func fetchAttendanceHistoryData(store: DataStore, month: Int, year: Int) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await store.fetchAttendanceHistoryByMonth(month: month, year: year)
            let attendanceHistoryData = response.list
            
            print(response)
            
            self.attendanceHistory = attendanceHistoryData.map { Attendance(from: $0) }
//            let mappedHistory = attendanceHistoryData.map { Attendance(from: $0) }
//            self.attendanceHistory = mappedHistory.isEmpty || !Self.history(mappedHistory, matchesMonth: month, year: year)
//                ? Self.mockAttendanceHistory(month: month, year: year)
//                : mappedHistory
            
        } catch let error as ApiError {
            self.errorMessage = "\(error.error ?? "") - \(error.message ?? "")"
            self.attendanceHistory = []
//            self.attendanceHistory = Self.mockAttendanceHistory(month: month, year: year)
        } catch {
            self.errorMessage = "An unexpected error occurred."
            self.attendanceHistory = []
//            self.attendanceHistory = Self.mockAttendanceHistory(month: month, year: year)
        }
        
        isLoading = false
    }

//    private static func history(_ history: [Attendance], matchesMonth month: Int, year: Int) -> Bool {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "E, d MMM yyyy"
//        formatter.locale = Locale(identifier: "en_US_POSIX")
//
//        return history.contains { attendance in
//            guard let date = formatter.date(from: attendance.date) else { return false }
//            let components = Calendar.current.dateComponents([.month, .year], from: date)
//            return components.month == month && components.year == year
//        }
//    }
//
//    private static func mockAttendanceHistory(month: Int, year: Int) -> [Attendance] {
//        switch (month, year) {
//        case (5, 2026):
//            return [
//                Attendance(date: "Fri, 29 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:03 AM - 05:01 PM", status: .onTime),
//                Attendance(date: "Thu, 28 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:31 AM - 05:08 PM", status: .late),
//                Attendance(date: "Wed, 27 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "-", status: .leave),
//                Attendance(date: "Tue, 26 May 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "07:55 AM - 05:00 PM", status: .onTime)
//            ]
//        case (6, 2026):
//            return [
//                Attendance(date: "Fri, 26 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:00 AM - 05:05 PM", status: .onTime),
//                Attendance(date: "Thu, 25 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:14 AM - 05:10 PM", status: .onTime),
//                Attendance(date: "Wed, 24 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:28 AM - 05:03 PM", status: .late),
//                Attendance(date: "Tue, 23 Jun 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "07:58 AM - 05:00 PM", status: .onTime)
//            ]
//        case (7, 2026):
//            return [
//                Attendance(date: "Wed, 9 Jul 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "-", status: .leave),
//                Attendance(date: "Tue, 8 Jul 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:25 AM - 05:10 PM", status: .late),
//                Attendance(date: "Mon, 7 Jul 2026", checkedInAt: nil, checkedOutAt: nil, timeRangeLabel: "08:00 AM - 05:05 PM", status: .onTime)
//            ]
//        default:
//            return []
//        }
//    }
}
