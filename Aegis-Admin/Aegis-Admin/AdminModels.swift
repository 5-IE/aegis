import Foundation

enum AdminSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case liveRadar = "Live Radar"
    case administration = "Administration"
    case reports = "Reports"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .liveRadar:
            return "map"
        case .administration:
            return "person"
        case .reports:
            return "doc.text"
        case .settings:
            return "gearshape"
        }
    }
}

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

struct UserSession: Codable, Equatable {
    let id: Int
    let username: String
    let role: String
    let session: String?
    let firstName: String?
    let lastName: String?
    let email: String

    var displayName: String {
        let joined = [firstName, lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? username : joined
    }
}

struct DashboardSummary: Equatable {
    let onTime: Int
    let lateClockIn: Int
    let absent: Int
    let noClockIn: Int

    static let empty = DashboardSummary(onTime: 0, lateClockIn: 0, absent: 0, noClockIn: 0)
}

struct AttendanceOverviewRow: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let session: String
    let clockedInAt: String?
    let clockedOutAt: String?
    let status: String
}

struct Room: Identifiable, Equatable {
    let id: Int
    let name: String
}

struct RadarPoint: Identifiable, Equatable {
    let id: Int
    let userName: String
    let session: String?
    let x: Double
    let y: Double
}

struct Occupant: Identifiable, Equatable {
    let id: Int
    let learner: String
    let session: String
    let durationSeconds: Int
    let status: String

    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct RoomMetrics: Equatable {
    let temperature: Double
    let humidity: Double
    let peopleInRoom: Int

    static let empty = RoomMetrics(temperature: 0, humidity: 0, peopleInRoom: 0)
}

struct SessionConfig: Equatable {
    var startTime: String
    var lateAfter: String
    var endTime: String
}

struct SessionConfigs: Equatable {
    var am: SessionConfig
    var pm: SessionConfig

    static let empty = SessionConfigs(
        am: SessionConfig(startTime: "08:00:00", lateAfter: "08:15:00", endTime: "12:00:00"),
        pm: SessionConfig(startTime: "13:00:00", lateAfter: "13:15:00", endTime: "17:00:00")
    )
}

struct SystemConfig: Equatable {
    var presenceStalenessMinutes: Int
    var timezone: String

    static let empty = SystemConfig(presenceStalenessMinutes: 5, timezone: "Asia/Jakarta")
}

enum SessionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case am = "AM"
    case pm = "PM"

    var id: String { rawValue }
    var queryValue: String? { self == .all ? nil : rawValue }
}

extension String {
    var titleCasedStatus: String {
        switch self {
        case "Not Checked In":
            return "Not checked in"
        case "Running Late":
            return "Running late"
        case "Checked In":
            return "Checked in"
        case "Checked Out":
            return "Checked out"
        case "Not Checked Out":
            return "Not checked out"
        default:
            return self
        }
    }
}
