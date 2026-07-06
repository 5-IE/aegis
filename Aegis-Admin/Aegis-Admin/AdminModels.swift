import Combine
import Foundation

enum AdminSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case liveRadar = "Live Radar"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .dashboard:
            return "clipboard"
        case .liveRadar:
            return "map"
        case .settings:
            return "gearshape"
        }
    }
}

struct DashboardSnapshot {
    let onTime: Int
    let lateClockIn: Int
    let absent: Int
    let noClockIn: Int

    static let mock = DashboardSnapshot(
        onTime: 120,
        lateClockIn: 2,
        absent: 0,
        noClockIn: 0
    )
}

enum RadarStatus {
    case active
    case inactive
}

struct RadarPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let status: RadarStatus
}

struct Beacon: Identifiable {
    let id = UUID()
    let label: String
    let x: Double
    let y: Double
}

struct Occupant: Identifiable {
    let id = UUID()
    let learner: String
    let session: String
    let duration: String
    let status: String
}

struct RoomSnapshot: Identifiable {
    let id: String
    let name: String
    let temperature: String
    let humidity: String
    let peopleCount: Int
    let beacons: [Beacon]
    let radarPoints: [RadarPoint]
    let occupants: [Occupant]

    private static let sampleBeacons = [
        Beacon(label: "B01", x: 0.055, y: 0.085),
        Beacon(label: "B02", x: 0.955, y: 0.085),
        Beacon(label: "B03", x: 0.50, y: 0.90)
    ]

    private static let sampleRadarPoints = [
        RadarPoint(x: 0.24, y: 0.36, status: .active),
        RadarPoint(x: 0.265, y: 0.39, status: .active),
        RadarPoint(x: 0.69, y: 0.25, status: .active),
        RadarPoint(x: 0.80, y: 0.59, status: .active),
        RadarPoint(x: 0.485, y: 0.59, status: .inactive)
    ]

    private static let sampleOccupants = [
        Occupant(learner: "Azzahra Dita Alfatrah", session: "PM", duration: "2h 20m", status: "Active"),
        Occupant(learner: "Steve Agustinus", session: "PM", duration: "1h 50m", status: "Active"),
        Occupant(learner: "Felicia Susanto", session: "PM", duration: "2h 20m", status: "Active"),
        Occupant(learner: "William Antoline", session: "PM", duration: "2h 05m", status: "Inactive"),
        Occupant(learner: "Hardy Tee", session: "PM", duration: "2h 34m", status: "Active")
    ]

    static let mockRooms: [RoomSnapshot] = [
        RoomSnapshot(
            id: "room-1",
            name: "Room 1",
            temperature: "22,5\u{00B0}C",
            humidity: "45%",
            peopleCount: 25,
            beacons: sampleBeacons,
            radarPoints: sampleRadarPoints,
            occupants: sampleOccupants
        ),
        RoomSnapshot.demo(id: "room-2", name: "Room 2", temperature: "23,1\u{00B0}C", humidity: "48%", peopleCount: 18),
        RoomSnapshot.demo(id: "room-3", name: "Room 3", temperature: "21,9\u{00B0}C", humidity: "43%", peopleCount: 21),
        RoomSnapshot.demo(id: "room-4", name: "Room 4", temperature: "22,7\u{00B0}C", humidity: "46%", peopleCount: 14),
        RoomSnapshot.demo(id: "room-5", name: "Room 5", temperature: "22,4\u{00B0}C", humidity: "44%", peopleCount: 16)
    ]

    private static func demo(id: String, name: String, temperature: String, humidity: String, peopleCount: Int) -> RoomSnapshot {
        RoomSnapshot(
            id: id,
            name: name,
            temperature: temperature,
            humidity: humidity,
            peopleCount: peopleCount,
            beacons: sampleBeacons,
            radarPoints: sampleRadarPoints,
            occupants: sampleOccupants
        )
    }
}

protocol AdminDataProviding {
    var dashboard: DashboardSnapshot { get }
    var rooms: [RoomSnapshot] { get }
}

struct MockAdminDataProvider: AdminDataProviding {
    let dashboard = DashboardSnapshot.mock
    let rooms = RoomSnapshot.mockRooms
}

@MainActor
final class AdminViewModel: ObservableObject {
    @Published var selectedSection: AdminSection = .dashboard
    @Published var selectedRoomID = RoomSnapshot.mockRooms[0].id
    @Published var dashboard: DashboardSnapshot
    @Published var rooms: [RoomSnapshot]

    init() {
        let dataProvider = MockAdminDataProvider()
        self.dashboard = dataProvider.dashboard
        self.rooms = dataProvider.rooms
        self.selectedRoomID = dataProvider.rooms[0].id
    }

    init(dataProvider: AdminDataProviding) {
        self.dashboard = dataProvider.dashboard
        self.rooms = dataProvider.rooms
        self.selectedRoomID = dataProvider.rooms[0].id
    }

    var selectedRoom: RoomSnapshot {
        rooms.first { $0.id == selectedRoomID } ?? rooms[0]
    }
}
