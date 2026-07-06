//
//  AttendanceData.swift
//  Aegis
//
//  Created by Steve Agustinus on 07/07/26.
//

import Foundation
import SwiftUI

struct Attendance: Identifiable {
    var id: String { date }
    
    let date: String
    let checkedInAt: Date?
    let checkedOutAt: Date?
    let timeRangeLabel: String
    let status: AttendanceStatus
}

extension Attendance {
    init(from apiModel: AttendanceData) {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "E, d MMM yyyy"
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = inputFormatter.date(from: apiModel.date) {
            self.date = outputFormatter.string(from: date)
        } else {
            self.date = ""
        }
        
        self.checkedInAt = apiModel.checkedInAt
        self.checkedOutAt = apiModel.checkedOutAt
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "hh:mm a"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let checkedInAt, let checkedOutAt {
            self.timeRangeLabel = "\(timeFormatter.string(from: checkedInAt)) - \(timeFormatter.string(from: checkedOutAt))"
        } else {
            self.timeRangeLabel = "-"
        }

        switch (apiModel.status) {
        case "early": self.status = .onTime
        case "late": self.status = .late
        case "leave": self.status = .leave
        default: self.status = .leave
        }
    }
}

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
