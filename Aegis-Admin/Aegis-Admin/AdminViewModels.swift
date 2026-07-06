import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var isSigningIn = false
    @Published var disabledFeatureMessage: String?

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !isSigningIn
    }

    func signIn(sessionStore: SessionStore) async {
        guard canSubmit else { return }
        isSigningIn = true
        await sessionStore.signIn(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        isSigningIn = false
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var summary = DashboardSummary.empty
    @Published var overviewRows: [AttendanceOverviewRow] = []
    @Published var state: LoadState = .idle
    @Published var searchText = ""
    @Published var sessionFilter: SessionFilter = .all

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMMM yyyy"
        return formatter.string(from: Date())
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: Date())
    }

    func load(sessionStore: SessionStore) async {
        state = .loading
        do {
            async let summary = sessionStore.dashboardSummary()
            async let rows = sessionStore.overview(search: searchText, sessionFilter: sessionFilter)
            self.summary = try await summary
            self.overviewRows = try await rows
            state = overviewRows.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(readableMessage(for: error))
        }
    }

    func reloadOverview(sessionStore: SessionStore) async {
        do {
            overviewRows = try await sessionStore.overview(search: searchText, sessionFilter: sessionFilter)
            state = overviewRows.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(readableMessage(for: error))
        }
    }
}

@MainActor
final class LiveRadarViewModel: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selectedRoomID: Int?
    @Published var radarPoints: [RadarPoint] = []
    @Published var occupants: [Occupant] = []
    @Published var metrics = RoomMetrics.empty
    @Published var state: LoadState = .idle
    @Published var occupantsSearchText = ""

    private var pollTask: Task<Void, Never>?

    var selectedRoom: Room? {
        rooms.first { $0.id == selectedRoomID }
    }

    var filteredOccupants: [Occupant] {
        let trimmed = occupantsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return occupants }
        return occupants.filter { $0.learner.localizedCaseInsensitiveContains(trimmed) }
    }

    func load(sessionStore: SessionStore) async {
        state = .loading
        do {
            let rooms = try await sessionStore.rooms()
            self.rooms = rooms
            if selectedRoomID == nil || !rooms.contains(where: { $0.id == selectedRoomID }) {
                selectedRoomID = rooms.first?.id
            }
            guard let selectedRoomID else {
                state = .empty
                return
            }
            try await loadSelectedRoom(sessionStore: sessionStore, roomID: selectedRoomID)
            state = .loaded
        } catch {
            state = .failed(readableMessage(for: error))
        }
    }

    func select(roomID: Int, sessionStore: SessionStore) {
        selectedRoomID = roomID
        Task {
            do {
                try await loadSelectedRoom(sessionStore: sessionStore, roomID: roomID)
                state = .loaded
            } catch {
                state = .failed(readableMessage(for: error))
            }
        }
    }

    func startPolling(sessionStore: SessionStore) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if let roomID = selectedRoomID {
                    do {
                        try await loadSelectedRoom(sessionStore: sessionStore, roomID: roomID)
                        state = .loaded
                    } catch {
                        state = .failed(readableMessage(for: error))
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loadSelectedRoom(sessionStore: SessionStore, roomID: Int) async throws {
        async let points = sessionStore.roomMap(roomID: roomID)
        async let occupants = sessionStore.currentOccupants(roomID: roomID)
        async let metrics = sessionStore.roomMetrics(roomID: roomID)
        self.radarPoints = try await points
        self.occupants = try await occupants
        self.metrics = try await metrics
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var sessionConfigs = SessionConfigs.empty
    @Published var systemConfig = SystemConfig.empty
    @Published var state: LoadState = .idle
    @Published var saveMessage: String?
    @Published var isSaving = false

    func load(sessionStore: SessionStore) async {
        state = .loading
        do {
            async let sessionConfigs = sessionStore.sessionConfigs()
            async let systemConfig = sessionStore.systemConfig()
            self.sessionConfigs = try await sessionConfigs
            self.systemConfig = try await systemConfig
            state = .loaded
        } catch {
            state = .failed(readableMessage(for: error))
        }
    }

    func save(sessionStore: SessionStore) async {
        isSaving = true
        saveMessage = nil
        do {
            try await sessionStore.updateSessionConfig(session: "AM", config: sessionConfigs.am)
            try await sessionStore.updateSessionConfig(session: "PM", config: sessionConfigs.pm)
            try await sessionStore.updateSystemConfig(systemConfig)
            saveMessage = "Settings saved"
            state = .loaded
        } catch {
            saveMessage = readableMessage(for: error)
            state = .failed(readableMessage(for: error))
        }
        isSaving = false
    }
}

func readableMessage(for error: Error) -> String {
    if let apiError = error as? AegisAPIError {
        return apiError.localizedDescription
    }
    return error.localizedDescription
}
