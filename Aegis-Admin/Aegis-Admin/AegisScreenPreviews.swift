import SwiftUI

#if DEBUG
@MainActor
enum AegisPreviewData {
    static let sessionStore = SessionStore()

    static let adminUser = UserSession(
        id: 1,
        username: "admin",
        role: "admin",
        session: nil,
        firstName: "Aegis",
        lastName: "Admin",
        email: "admin@aegis.local"
    )

    static func dashboardViewModel() -> DashboardViewModel {
        let viewModel = DashboardViewModel()
        viewModel.summary = DashboardSummary(onTime: 84, lateClockIn: 2, absent: 2, noClockIn: 10)
        viewModel.overviewRows = [
            AttendanceOverviewRow(name: "Azzahra Dita Alfatirah", session: "PM", clockedInAt: "2026-07-08T12:50:00Z", clockedOutAt: nil, status: "On time"),
            AttendanceOverviewRow(name: "Felicia Susanto", session: "PM", clockedInAt: "2026-07-08T12:30:00Z", clockedOutAt: nil, status: "On time"),
            AttendanceOverviewRow(name: "Steve Agustinus", session: "PM", clockedInAt: "2026-07-08T12:30:00Z", clockedOutAt: nil, status: "On time"),
            AttendanceOverviewRow(name: "Hardy Tee", session: "PM", clockedInAt: "2026-07-08T12:50:00Z", clockedOutAt: nil, status: "Running Late"),
            AttendanceOverviewRow(name: "William Antoine", session: "PM", clockedInAt: "2026-07-08T12:30:00Z", clockedOutAt: nil, status: "Checked In")
        ]
        viewModel.state = .loaded
        return viewModel
    }

    static func liveRadarViewModel() -> LiveRadarViewModel {
        let viewModel = LiveRadarViewModel()
        viewModel.rooms = [
            Room(id: 1, name: "North Wing"),
            Room(id: 2, name: "South Wing"),
            Room(id: 3, name: "Room 3")
        ]
        viewModel.selectedRoomID = 1
        viewModel.radarPoints = [
            RadarPoint(id: 1, userName: "Felicia Susanto", session: "PM", x: 0.25, y: 0.42),
            RadarPoint(id: 2, userName: "William Antoine", session: "PM", x: 0.62, y: 0.48),
            RadarPoint(id: 3, userName: "Hardy Tee", session: "PM", x: 0.50, y: 0.70)
        ]
        viewModel.occupants = [
            Occupant(id: 1, learner: "Felicia Susanto", session: "PM", durationSeconds: 1680, status: "Checked In"),
            Occupant(id: 2, learner: "William Antoine", session: "PM", durationSeconds: 2430, status: "Checked In"),
            Occupant(id: 3, learner: "Hardy Tee", session: "PM", durationSeconds: 780, status: "Running Late")
        ]
        viewModel.metrics = RoomMetrics(temperature: 26.4, humidity: 62, peopleInRoom: 3)
        viewModel.state = .loaded
        return viewModel
    }

    static func administrationViewModel() -> AdministrationViewModel {
        let viewModel = AdministrationViewModel()
        viewModel.users = [
            AdminUser(id: 1, username: "admin", email: "admin@aegis.local", role: .admin, session: nil, firstName: "Aegis", lastName: "Admin", isActive: true, createdAt: nil),
            AdminUser(id: 2, username: "felicia", email: "felicia@aegis.local", role: .learner, session: "PM", firstName: "Felicia", lastName: "Susanto", isActive: true, createdAt: nil),
            AdminUser(id: 3, username: "william", email: "william@aegis.local", role: .learner, session: "PM", firstName: "William", lastName: "Antoine", isActive: true, createdAt: nil)
        ]
        viewModel.total = viewModel.users.count
        viewModel.rooms = [
            Room(id: 1, name: "North Wing"),
            Room(id: 2, name: "South Wing")
        ]
        viewModel.beacons = [
            AdminBeacon(id: 1, name: "Beacon 01", beaconIdentifier: "B01-NORTH", roomID: 1, roomName: "North Wing"),
            AdminBeacon(id: 2, name: "Beacon 02", beaconIdentifier: "B02-SOUTH", roomID: 2, roomName: "South Wing")
        ]
        viewModel.beaconTotal = viewModel.beacons.count
        viewModel.state = .loaded
        viewModel.roomState = .loaded
        viewModel.beaconState = .loaded
        return viewModel
    }

    static func reportsViewModel() -> ReportsViewModel {
        let viewModel = ReportsViewModel()
        viewModel.dateText = "2026-07-08"
        viewModel.userIDText = ""
        viewModel.result = RollupResult(processed: 96, skippedLeave: 4)
        viewModel.message = "Rollup completed"
        viewModel.state = .loaded
        return viewModel
    }

    static func settingsViewModel() -> SettingsViewModel {
        let viewModel = SettingsViewModel()
        viewModel.sessionConfigs = SessionConfigs(
            am: SessionConfig(startTime: "08:00:00", lateAfter: "08:15:00", endTime: "12:00:00"),
            pm: SessionConfig(startTime: "13:00:00", lateAfter: "13:15:00", endTime: "17:00:00")
        )
        viewModel.systemConfig = SystemConfig(presenceStalenessMinutes: 5, timezone: "Asia/Jakarta")
        viewModel.state = .loaded
        return viewModel
    }
}

struct AegisScreenPreviews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            LoginView(sessionStore: AegisPreviewData.sessionStore)
                .previewDisplayName("Login")

            DashboardView(
                viewModel: AegisPreviewData.dashboardViewModel(),
                sessionStore: AegisPreviewData.sessionStore
            )
            .previewDisplayName("Dashboard")

            LiveRadarView(
                viewModel: AegisPreviewData.liveRadarViewModel(),
                sessionStore: AegisPreviewData.sessionStore
            )
            .previewDisplayName("Live Radar")

            AdministrationView(
                viewModel: AegisPreviewData.administrationViewModel(),
                sessionStore: AegisPreviewData.sessionStore,
                currentAdminID: AegisPreviewData.adminUser.id
            )
            .previewDisplayName("Administration")

            ReportsView(
                viewModel: AegisPreviewData.reportsViewModel(),
                sessionStore: AegisPreviewData.sessionStore
            )
            .previewDisplayName("Reports")

            SettingsView(
                viewModel: AegisPreviewData.settingsViewModel(),
                sessionStore: AegisPreviewData.sessionStore
            )
            .previewDisplayName("Settings")
        }
        .frame(width: 1180, height: 760)
    }
}
#endif
