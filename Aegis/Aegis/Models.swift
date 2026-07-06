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

// MARK: - Today's Attendance Status
enum TodayAttendanceStatus: Identifiable {
    case checkedIn(time: String)
    case runningLate(time: String)
    case notCheckedIn
    case onLeave

    var id: String {
        switch self {
        case .checkedIn: return "checkedIn"
        case .runningLate: return "runningLate"
        case .notCheckedIn: return "notCheckedIn"
        case .onLeave: return "onLeave"
        }
    }

    var title: String {
        switch self {
        case .checkedIn: return "Checked In!"
        case .runningLate: return "Running Late"
        case .notCheckedIn: return "Not Checked In"
        case .onLeave: return "On Leave"
        }
    }

    var message: String {
        switch self {
        case .checkedIn: return "You're all set for today."
        case .runningLate: return "Let's be on time tomorrow."
        case .notCheckedIn: return "Don't forget to check in."
        case .onLeave: return "Hope to see you back soon."
        }
    }

    var detail: String {
        switch self {
        case .checkedIn(let time):
            return "Checked in at \(time)"
        case .runningLate(let time):
            return "Checked in at \(time)"
        case .notCheckedIn:
            return "No check-in reported yet."
        case .onLeave:
            return "Leave recorded for today."
        }
    }

    var accentColor: Color {
        switch self {
        case .checkedIn: return Theme.onTime
        case .runningLate: return Theme.late
        case .notCheckedIn: return Theme.notCheckedIn
        case .onLeave: return Theme.leave
        }
    }

    var backgroundColor: Color {
        switch self {
        case .checkedIn: return Theme.todayCheckedInBackground
        case .runningLate: return Theme.todayLateBackground
        case .notCheckedIn: return Theme.todayNotCheckedInBackground
        case .onLeave: return Theme.todayLeaveBackground
        }
    }

    var illustrationFadeColor: Color {
        switch self {
        case .checkedIn: return Theme.todayCheckedInFade
        case .runningLate: return Theme.todayLateFade
        case .notCheckedIn: return Theme.todayNotCheckedInFade
        case .onLeave: return Theme.todayLeaveFade
        }
    }

    var statusIcon: String {
        switch self {
        case .checkedIn: return "checkmark.circle.fill"
        case .runningLate: return "clock.fill"
        case .notCheckedIn: return "exclamationmark.circle.fill"
        case .onLeave: return "xmark.fill"
        }
    }

    var illustrationAsset: String {
        switch self {
        case .checkedIn: return "10"
        case .onLeave: return "11"
        case .notCheckedIn: return "12"
        case .runningLate: return "13"
        }
    }
}

// MARK: - Sample Data
enum SampleData {
    static let todayAttendanceOptions: [TodayAttendanceStatus] = [
        .checkedIn(time: "12:55PM"),
        .runningLate(time: "13:05PM"),
        .notCheckedIn,
        .onLeave
    ]

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
