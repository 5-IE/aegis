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

enum AdministrationMode: String, CaseIterable, Identifiable {
    case users = "User Management"
    case rooms = "Room Management"
    case beacons = "Beacon Management"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .users:
            return "person.3.fill"
        case .rooms:
            return "building.2.fill"
        case .beacons:
            return "sensor.tag.radiowaves.forward.fill"
        }
    }
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

enum AttendanceStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case onTime = "On-time"
    case late = "Late"
    case leave = "Leave"

    var id: String { rawValue }

    func matches(_ status: String) -> Bool {
        let value = status.lowercased()
        switch self {
        case .onTime:
            return value.contains("on time") || value.contains("checked in") || value.contains("early")
        case .late:
            return value.contains("late") || value.contains("running")
        case .leave:
            return value.contains("leave") || value.contains("checked out")
        }
    }
}

enum OccupantStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case active = "Active"
    case inactive = "Inactive"

    var id: String { rawValue }

    func matches(_ status: String) -> Bool {
        let value = status.lowercased()
        switch self {
        case .active:
            return value.contains("on time") || value.contains("checked in") ||
                (value.contains("active") && !value.contains("inactive")) ||
                value.contains("early") || value.contains("late") ||
                value.contains("running")
        case .inactive:
            return value.contains("leave") || value.contains("clocked out") ||
                value.contains("inactive")
        }
    }
}

enum AdminUserRole: String, CaseIterable, Identifiable {
    case learner
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .learner:
            return "Learner"
        case .admin:
            return "Admin"
        }
    }
}

enum AdminUserRoleFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case learner = "Learner"
    case admin = "Admin"

    var id: String { rawValue }

    var queryValue: String? {
        switch self {
        case .all:
            return nil
        case .learner:
            return AdminUserRole.learner.rawValue
        case .admin:
            return AdminUserRole.admin.rawValue
        }
    }
}

struct AdminUser: Identifiable, Equatable {
    let id: Int
    let username: String
    let email: String
    let role: AdminUserRole
    let session: String?
    let firstName: String?
    let lastName: String?
    let isActive: Bool
    let createdAt: String?

    var displayName: String {
        let joined = [firstName, lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? username : joined
    }

    var sessionDisplay: String {
        role == .learner ? (session ?? "-") : "-"
    }

    var statusText: String {
        isActive ? "Active" : "Inactive"
    }
}

struct AdminUsersPage: Equatable {
    let users: [AdminUser]
    let total: Int
    let page: Int
    let perPage: Int
}

struct AdminRoomForm: Identifiable, Equatable {
    let formID = UUID()
    var roomID: Int?
    var name = ""

    var id: UUID { formID }
    var isEditing: Bool { roomID != nil }
    var title: String { isEditing ? "Edit Room" : "Add New Room" }
    var submitTitle: String { isEditing ? "Save Room" : "Create New Room" }
    var canSubmit: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {}

    init(room: Room) {
        self.roomID = room.id
        self.name = room.name
    }
}

enum BeaconAssignmentFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case assigned = "Assigned"
    case unassigned = "Unassigned"

    var id: String { rawValue }

    var queryValue: Bool? {
        switch self {
        case .all:
            return nil
        case .assigned:
            return true
        case .unassigned:
            return false
        }
    }
}

struct AdminBeacon: Identifiable, Equatable {
    let id: Int
    let name: String
    let beaconIdentifier: String
    let roomID: Int?
    let roomName: String?

    var assignmentText: String {
        roomName ?? "Unassigned"
    }

    var statusText: String {
        roomID == nil ? "Unassigned" : "Assigned"
    }
}

struct AdminBeaconsPage: Equatable {
    let beacons: [AdminBeacon]
    let total: Int
    let page: Int
    let perPage: Int
}

struct AdminBeaconForm: Identifiable, Equatable {
    let formID = UUID()
    var beaconID: Int?
    var name = ""
    var beaconIdentifier = ""
    var roomID: Int?

    var id: UUID { formID }
    var isEditing: Bool { beaconID != nil }
    var title: String { isEditing ? "Edit Beacon" : "Register New Beacon" }
    var submitTitle: String { isEditing ? "Save Beacon" : "Register Beacon" }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !beaconIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    init(beacon: AdminBeacon) {
        self.beaconID = beacon.id
        self.name = beacon.name
        self.beaconIdentifier = beacon.beaconIdentifier
        self.roomID = beacon.roomID
    }
}

struct AdminUserForm: Identifiable, Equatable {
    let formID = UUID()
    var userID: Int?
    var username = ""
    var password = ""
    var email = ""
    var role: AdminUserRole = .learner
    var session = ""
    var firstName = ""
    var lastName = ""

    var id: UUID { formID }
    var isEditing: Bool { userID != nil }

    var title: String {
        isEditing ? "Edit Learner" : "Add New Learner"
    }

    var submitTitle: String {
        isEditing ? "Edit Learner Profile" : "Create Learner Profile"
    }

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isEditing || !password.isEmpty) &&
        (role == .admin || !session.isEmpty)
    }

    init() {}

    init(user: AdminUser) {
        self.userID = user.id
        self.username = user.username
        self.email = user.email
        self.role = user.role
        self.session = user.session ?? "AM"
        self.firstName = user.firstName ?? ""
        self.lastName = user.lastName ?? ""
    }
}

struct RollupResult: Equatable {
    let processed: Int
    let skippedLeave: Int
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
