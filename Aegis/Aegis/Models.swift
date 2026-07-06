import SwiftUI

// MARK: - Attendance Status
enum AttendanceStatus: String {
    case onTime = "On-time"
    case late = "Late"
    case leave = "Leave"

    var color: Color {
        switch self {
        case .onTime: return Theme.onTime
        case .late: return Theme.late
        case .leave: return Theme.leave
        }
    }

    var backgroundColor: Color {
        switch self {
        case .onTime: return Theme.onTimeBackground
        case .late: return Theme.lateBackground
        case .leave: return Theme.leaveBackground
        }
    }
}

// MARK: - Attendance Record
struct AttendanceRecord: Identifiable {
    let id = UUID()
    let dateLabel: String   // e.g. "Fri, 26 Jun 2026"
    let timeRange: String   // e.g. "12:30PM - 17:15PM"
    let status: AttendanceStatus
}

// MARK: - Sample Data
enum SampleData {
    static let recentAttendance: [AttendanceRecord] = [
        AttendanceRecord(dateLabel: "Fri, 26 Jun 2026", timeRange: "12:30PM - 17:15PM", status: .onTime),
        AttendanceRecord(dateLabel: "Thu, 25 Jun 2026", timeRange: "12:55PM - 17:00PM", status: .onTime),
        AttendanceRecord(dateLabel: "Wed, 24 Jun 2026", timeRange: "13:05PM - 17:15PM", status: .late),
        AttendanceRecord(dateLabel: "Tue, 23 Jun 2026", timeRange: "12:50PM - 17:10PM", status: .onTime),
        AttendanceRecord(dateLabel: "Mon, 22 Jun 2026", timeRange: "-", status: .leave)
    ]

    static let juneHistory: [AttendanceRecord] = recentAttendance + [
        AttendanceRecord(dateLabel: "Fri, 19 Jun 2026", timeRange: "12:30PM - 17:15PM", status: .onTime),
        AttendanceRecord(dateLabel: "Thu, 18 Jun 2026", timeRange: "12:55PM - 17:00PM", status: .onTime),
        AttendanceRecord(dateLabel: "Wed, 17 Jun 2026", timeRange: "13:05PM - 17:15PM", status: .late),
        AttendanceRecord(dateLabel: "Tue, 16 Jun 2026", timeRange: "12:50PM - 17:10PM", status: .onTime),
        AttendanceRecord(dateLabel: "Mon, 15 Jun 2026", timeRange: "12:55PM - 17:00PM", status: .onTime),
        AttendanceRecord(dateLabel: "Fri, 12 Jun 2026", timeRange: "12:30PM - 17:15PM", status: .onTime)
    ]
}
