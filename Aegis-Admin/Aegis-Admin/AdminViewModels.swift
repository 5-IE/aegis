import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var isSigningIn = false
    @Published var validationMessage: String?

    var canSubmit: Bool {
        !isSigningIn
    }

    func signIn(sessionStore: SessionStore) async {
        guard canSubmit else { return }
        validationMessage = nil
        sessionStore.clearAuthError()

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            validationMessage = "Enter your email or phone."
            return
        }

        guard !password.isEmpty else {
            validationMessage = "Enter your password."
            return
        }

        isSigningIn = true
        await sessionStore.signIn(username: trimmedUsername, password: password)
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

@MainActor
final class AdministrationViewModel: ObservableObject {
    @Published var selectedMode: AdministrationMode = .users
    @Published var users: [AdminUser] = []
    @Published var total = 0
    @Published var page = 1
    @Published var perPage = 20
    @Published var searchText = ""
    @Published var roleFilter: AdminUserRoleFilter = .all
    @Published var sessionFilter: SessionFilter = .all
    @Published var includeInactive = false
    @Published var state: LoadState = .idle
    @Published var actionMessage: String?
    @Published var isSaving = false
    @Published var rooms: [Room] = []
    @Published var roomState: LoadState = .idle
    @Published var roomActionMessage: String?
    @Published var beacons: [AdminBeacon] = []
    @Published var beaconState: LoadState = .idle
    @Published var beaconActionMessage: String?
    @Published var beaconSearchText = ""
    @Published var beaconAssignmentFilter: BeaconAssignmentFilter = .all
    @Published var beaconRoomFilterID: Int?
    @Published var beaconTotal = 0
    @Published var beaconPage = 1
    @Published var beaconPerPage = 20

    var canGoPrevious: Bool { page > 1 }
    var canGoNext: Bool { page * perPage < total }
    var canGoPreviousBeaconPage: Bool { beaconPage > 1 }
    var canGoNextBeaconPage: Bool { beaconPage * beaconPerPage < beaconTotal }

    var filteredBeacons: [AdminBeacon] {
        let trimmed = beaconSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return beacons }
        return beacons.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.beaconIdentifier.localizedCaseInsensitiveContains(trimmed) ||
            ($0.roomName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var pageSummary: String {
        guard total > 0 else { return "Showing 0 users" }
        let start = ((page - 1) * perPage) + 1
        let end = min(page * perPage, total)
        return "Showing \(start)-\(end) of \(total) users"
    }

    var beaconPageSummary: String {
        guard beaconTotal > 0 else { return "Showing 0 beacons" }
        let start = ((beaconPage - 1) * beaconPerPage) + 1
        let end = min(beaconPage * beaconPerPage, beaconTotal)
        return "Showing \(start)-\(end) of \(beaconTotal) beacons"
    }

    func selectMode(_ mode: AdministrationMode, sessionStore: SessionStore) {
        selectedMode = mode
        Task {
            switch mode {
            case .users:
                if state == .idle {
                    await load(sessionStore: sessionStore)
                }
            case .rooms:
                if roomState == .idle {
                    await loadRooms(sessionStore: sessionStore)
                }
            case .beacons:
                if beaconState == .idle {
                    await loadBeacons(sessionStore: sessionStore)
                }
            }
        }
    }

    func load(sessionStore: SessionStore) async {
        state = .loading
        await fetch(sessionStore: sessionStore)
    }

    func applyFilters(sessionStore: SessionStore) async {
        page = 1
        await fetch(sessionStore: sessionStore)
    }

    func nextPage(sessionStore: SessionStore) async {
        guard canGoNext else { return }
        page += 1
        await fetch(sessionStore: sessionStore)
    }

    func previousPage(sessionStore: SessionStore) async {
        guard canGoPrevious else { return }
        page -= 1
        await fetch(sessionStore: sessionStore)
    }

    func save(form: AdminUserForm, sessionStore: SessionStore) async -> Bool {
        guard form.canSubmit else {
            actionMessage = "Please complete the required fields."
            return false
        }
        isSaving = true
        actionMessage = nil
        do {
            if let userID = form.userID {
                _ = try await sessionStore.updateAdminUser(id: userID, form: form)
                actionMessage = "User updated"
            } else {
                _ = try await sessionStore.createAdminUser(form)
                actionMessage = "User created"
            }
            await fetch(sessionStore: sessionStore)
            isSaving = false
            return true
        } catch {
            actionMessage = readableMessage(for: error)
            state = .failed(readableMessage(for: error))
            isSaving = false
            return false
        }
    }

    func resetPassword(user: AdminUser, newPassword: String, sessionStore: SessionStore) async -> Bool {
        guard !newPassword.isEmpty else {
            actionMessage = "Enter a new password."
            return false
        }
        isSaving = true
        actionMessage = nil
        do {
            try await sessionStore.resetAdminUserPassword(id: user.id, newPassword: newPassword)
            actionMessage = "Password reset"
            isSaving = false
            return true
        } catch {
            actionMessage = readableMessage(for: error)
            isSaving = false
            return false
        }
    }

    func delete(user: AdminUser, sessionStore: SessionStore) async {
        isSaving = true
        actionMessage = nil
        do {
            try await sessionStore.deleteAdminUser(id: user.id)
            actionMessage = "User deactivated"
            await fetch(sessionStore: sessionStore)
        } catch {
            actionMessage = readableMessage(for: error)
        }
        isSaving = false
    }

    func reactivate(user: AdminUser, sessionStore: SessionStore) async {
        isSaving = true
        actionMessage = nil
        do {
            try await sessionStore.reactivateAdminUser(id: user.id)
            actionMessage = "User reactivated"
            await fetch(sessionStore: sessionStore)
        } catch {
            actionMessage = readableMessage(for: error)
        }
        isSaving = false
    }

    func loadRooms(sessionStore: SessionStore) async {
        roomState = .loading
        await fetchRoomsAndBeaconSummary(sessionStore: sessionStore)
    }

    func saveRoom(form: AdminRoomForm, sessionStore: SessionStore) async -> Bool {
        guard form.canSubmit else {
            roomActionMessage = "Enter a room name."
            return false
        }
        isSaving = true
        roomActionMessage = nil
        do {
            if let roomID = form.roomID {
                _ = try await sessionStore.updateRoom(id: roomID, form: form)
                roomActionMessage = "Room updated"
            } else {
                _ = try await sessionStore.createRoom(form)
                roomActionMessage = "Room created"
            }
            await fetchRoomsAndBeaconSummary(sessionStore: sessionStore)
            isSaving = false
            return true
        } catch {
            roomActionMessage = readableMessage(for: error)
            roomState = .failed(readableMessage(for: error))
            isSaving = false
            return false
        }
    }

    func delete(room: Room, sessionStore: SessionStore) async {
        isSaving = true
        roomActionMessage = nil
        do {
            try await sessionStore.deleteRoom(id: room.id)
            roomActionMessage = "Room deleted"
            await fetchRoomsAndBeaconSummary(sessionStore: sessionStore)
        } catch {
            roomActionMessage = readableMessage(for: error)
        }
        isSaving = false
    }

    func loadBeacons(sessionStore: SessionStore) async {
        beaconState = .loading
        await fetchRoomsAndBeacons(sessionStore: sessionStore)
    }

    func applyBeaconFilters(sessionStore: SessionStore) async {
        beaconPage = 1
        await fetchRoomsAndBeacons(sessionStore: sessionStore)
    }

    func nextBeaconPage(sessionStore: SessionStore) async {
        guard canGoNextBeaconPage else { return }
        beaconPage += 1
        await fetchRoomsAndBeacons(sessionStore: sessionStore)
    }

    func previousBeaconPage(sessionStore: SessionStore) async {
        guard canGoPreviousBeaconPage else { return }
        beaconPage -= 1
        await fetchRoomsAndBeacons(sessionStore: sessionStore)
    }

    func saveBeacon(form: AdminBeaconForm, sessionStore: SessionStore) async -> Bool {
        guard form.canSubmit else {
            beaconActionMessage = "Complete beacon name and identifier."
            return false
        }
        isSaving = true
        beaconActionMessage = nil
        do {
            if let beaconID = form.beaconID {
                _ = try await sessionStore.updateAdminBeacon(id: beaconID, form: form)
                beaconActionMessage = "Beacon updated"
            } else {
                _ = try await sessionStore.createAdminBeacon(form)
                beaconActionMessage = "Beacon registered"
            }
            await fetchRoomsAndBeacons(sessionStore: sessionStore)
            isSaving = false
            return true
        } catch {
            beaconActionMessage = readableMessage(for: error)
            beaconState = .failed(readableMessage(for: error))
            isSaving = false
            return false
        }
    }

    func delete(beacon: AdminBeacon, sessionStore: SessionStore) async {
        isSaving = true
        beaconActionMessage = nil
        do {
            try await sessionStore.deleteAdminBeacon(id: beacon.id)
            beaconActionMessage = "Beacon deleted"
            await fetchRoomsAndBeacons(sessionStore: sessionStore)
        } catch {
            beaconActionMessage = readableMessage(for: error)
        }
        isSaving = false
    }

    func beaconCount(for room: Room) -> Int {
        beacons.filter { $0.roomID == room.id }.count
    }

    func beaconStatus(for room: Room) -> String {
        beaconCount(for: room) > 0 ? "Assigned" : "No beacons"
    }

    private func fetch(sessionStore: SessionStore) async {
        do {
            let result = try await sessionStore.adminUsers(
                search: searchText,
                roleFilter: roleFilter,
                sessionFilter: sessionFilter,
                includeInactive: includeInactive,
                page: page,
                perPage: perPage
            )
            users = result.users
            total = result.total
            page = result.page
            perPage = result.perPage
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(readableMessage(for: error))
        }
    }

    private func fetchRoomsAndBeaconSummary(sessionStore: SessionStore) async {
        do {
            async let rooms = sessionStore.rooms()
            async let beacons = sessionStore.adminBeacons(
                assignmentFilter: .all,
                roomID: nil,
                page: 1,
                perPage: 100
            )
            self.rooms = try await rooms
            let beaconPage = try await beacons
            self.beacons = beaconPage.beacons
            self.beaconTotal = beaconPage.total
            roomState = self.rooms.isEmpty ? .empty : .loaded
        } catch {
            roomState = .failed(readableMessage(for: error))
        }
    }

    private func fetchRoomsAndBeacons(sessionStore: SessionStore) async {
        do {
            async let rooms = sessionStore.rooms()
            async let beacons = sessionStore.adminBeacons(
                assignmentFilter: beaconAssignmentFilter,
                roomID: beaconRoomFilterID,
                page: beaconPage,
                perPage: beaconPerPage
            )
            self.rooms = try await rooms
            let result = try await beacons
            self.beacons = result.beacons
            self.beaconTotal = result.total
            self.beaconPage = result.page
            self.beaconPerPage = result.perPage
            beaconState = self.beacons.isEmpty ? .empty : .loaded
        } catch {
            beaconState = .failed(readableMessage(for: error))
        }
    }
}

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var dateText = ""
    @Published var userIDText = ""
    @Published var result: RollupResult?
    @Published var state: LoadState = .idle
    @Published var isRunning = false
    @Published var message: String?

    func runRollup(sessionStore: SessionStore) async {
        isRunning = true
        message = nil
        result = nil
        do {
            let trimmedDate = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUserID = userIDText.trimmingCharacters(in: .whitespacesAndNewlines)
            let userID: Int?
            if trimmedUserID.isEmpty {
                userID = nil
            } else if let parsed = Int(trimmedUserID), parsed > 0 {
                userID = parsed
            } else {
                message = "User ID must be a positive number."
                state = .failed(message ?? "Invalid user ID.")
                isRunning = false
                return
            }
            let output = try await sessionStore.runRollup(
                date: trimmedDate.isEmpty ? nil : trimmedDate,
                userID: userID
            )
            result = output
            message = "Rollup completed"
            state = .loaded
        } catch {
            message = readableMessage(for: error)
            state = .failed(readableMessage(for: error))
        }
        isRunning = false
    }
}

func readableMessage(for error: Error) -> String {
    if let apiError = error as? AegisAPIError {
        return apiError.localizedDescription
    }
    return error.localizedDescription
}
