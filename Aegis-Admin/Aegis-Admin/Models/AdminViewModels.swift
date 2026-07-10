import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var isSigningIn = false
    @Published var validationMessage: String?
    @Published var disabledFeatureMessage: String?

    var canSubmit: Bool {
        !isSigningIn
    }

    func signIn(sessionStore: SessionStore) async {
        guard canSubmit else { return }
        validationMessage = nil
        disabledFeatureMessage = nil
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
    @Published var statusFilters: Set<AttendanceStatusFilter> = []
    @Published var total = 0
    @Published var page = 1
    @Published var perPage = 100

    /// One in-flight overview load; a new intent cancels the prior one so a
    /// slow, stale response can never overwrite fresher state.
    private var overviewLoadTask: Task<Void, Never>?

    var canGoPrevious: Bool { page > 1 }
    var canGoNext: Bool { page * perPage < total }

    var pageSummary: String {
        guard total > 0 else { return "Showing 0 learners" }
        let start = ((page - 1) * perPage) + 1
        let end = min(page * perPage, total)
        return "Showing \(start)-\(end) of \(total) learners"
    }

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
            summary = try await sessionStore.dashboardSummary()
        } catch {
            state = .failed(readableMessage(for: error))
            return
        }
        await runOverviewFetch(sessionStore: sessionStore)
    }

    /// Filter/search change: reset to the first page and refetch.
    func applyFilters(sessionStore: SessionStore) async {
        page = 1
        await runOverviewFetch(sessionStore: sessionStore)
    }

    func reloadOverview(sessionStore: SessionStore) async {
        await applyFilters(sessionStore: sessionStore)
    }

    func nextPage(sessionStore: SessionStore) async {
        guard canGoNext else { return }
        page += 1
        await runOverviewFetch(sessionStore: sessionStore)
    }

    func previousPage(sessionStore: SessionStore) async {
        guard canGoPrevious else { return }
        page -= 1
        await runOverviewFetch(sessionStore: sessionStore)
    }

    /// Cancels any in-flight overview fetch and starts a fresh one, so a slow
    /// response for an old page/filter can never overwrite newer state.
    private func runOverviewFetch(sessionStore: SessionStore) async {
        overviewLoadTask?.cancel()
        let task = Task { await self.fetchOverview(sessionStore: sessionStore) }
        overviewLoadTask = task
        await task.value
    }

    private static func lastValidPage(total: Int, perPage: Int) -> Int {
        let size = max(perPage, 1)
        return max(1, Int((Double(total) / Double(size)).rounded(.up)))
    }

    private func fetchOverview(sessionStore: SessionStore) async {
        do {
            var result = try await sessionStore.overview(
                search: FormValidators.sanitizedSearchTerm(searchText),
                sessionFilter: sessionFilter,
                page: page,
                perPage: perPage
            )
            try Task.checkCancellation()
            // Clamp: a shrunken result set can leave the current page past the
            // end; refetch at the last valid page.
            let lastPage = Self.lastValidPage(total: result.total, perPage: result.perPage)
            if result.page > lastPage {
                result = try await sessionStore.overview(
                    search: FormValidators.sanitizedSearchTerm(searchText),
                    sessionFilter: sessionFilter,
                    page: lastPage,
                    perPage: perPage
                )
                try Task.checkCancellation()
            }
            overviewRows = applyStatusFilters(to: result.rows)
            total = result.total
            page = result.page
            perPage = result.perPage
            state = overviewRows.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            // Superseded by a newer fetch; let it own the state.
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(readableMessage(for: error))
        }
    }

    private func applyStatusFilters(to rows: [AttendanceOverviewRow]) -> [AttendanceOverviewRow] {
        guard !statusFilters.isEmpty else { return rows }
        return rows.filter { row in
            statusFilters.contains { $0.matches(row.status) }
        }
    }
}

@MainActor
final class LiveRadarViewModel: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selectedRoomID: Int?
    @Published var radarPoints: [RadarPoint] = []
    @Published var occupants: [Occupant] = []
    @Published var roomBeacons: [AdminBeacon] = []
    @Published var metrics = RoomMetrics.empty
    @Published var state: LoadState = .idle
    @Published var occupantsSearchText = ""
    @Published var occupantsSessionFilter: SessionFilter = .all
    @Published var occupantsStatusFilters: Set<OccupantStatusFilter> = [.active]

    private var pollTask: Task<Void, Never>?
    private var selectTask: Task<Void, Never>?
    /// Poll-error resilience: transient failures keep showing the last data
    /// (at most a few ticks stale) instead of blanking the whole radar.
    private var consecutivePollFailures = 0
    private static let maxConsecutivePollFailures = 3

    var selectedRoom: Room? {
        rooms.first { $0.id == selectedRoomID }
    }

    var filteredOccupants: [Occupant] {
        let trimmed = occupantsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return occupants.filter { occupant in
            let matchesName = trimmed.isEmpty || occupant.learner.localizedCaseInsensitiveContains(trimmed)
            let matchesSession = occupantsSessionFilter == .all ||
                occupant.session.caseInsensitiveCompare(occupantsSessionFilter.rawValue) == .orderedSame
            let matchesStatus = occupantsStatusFilters.isEmpty ||
                occupantsStatusFilters.contains { $0.matches(occupant.status) }
            return matchesName && matchesSession && matchesStatus
        }
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
        selectTask?.cancel()
        selectTask = Task {
            do {
                try await loadSelectedRoom(sessionStore: sessionStore, roomID: roomID)
                guard roomID == selectedRoomID else { return }
                consecutivePollFailures = 0
                state = .loaded
            } catch {
                // Cancellation surfaces as URLError wrapped in .network, not
                // CancellationError — check the task, not the error type.
                guard !Task.isCancelled, roomID == selectedRoomID else { return }
                state = .failed(readableMessage(for: error))
            }
        }
    }

    func startPolling(sessionStore: SessionStore) {
        pollTask?.cancel()
        consecutivePollFailures = 0
        pollTask = Task {
            while !Task.isCancelled {
                if let roomID = selectedRoomID {
                    do {
                        try await loadSelectedRoom(sessionStore: sessionStore, roomID: roomID)
                        guard roomID == selectedRoomID else { continue }
                        consecutivePollFailures = 0
                        state = .loaded
                    } catch {
                        // Teardown cancellation arrives as URLError(.cancelled)
                        // wrapped in .network; it must not count as a strike
                        // or write state.
                        if Task.isCancelled { break }
                        // An error for a room that is no longer selected is
                        // not a failure of the current view.
                        guard roomID == selectedRoomID else { continue }
                        // If the session died, SessionStore has already
                        // flipped to signedOut. For transient errors, keep
                        // showing the (\u{2264}15s stale) view for a few ticks
                        // before surfacing a failure. A loaded-but-empty room
                        // is still a valid view — only fail early when
                        // nothing was ever loaded.
                        consecutivePollFailures += 1
                        let hasLoadedView = state == .loaded
                        if !hasLoadedView || consecutivePollFailures >= Self.maxConsecutivePollFailures {
                            state = .failed(readableMessage(for: error))
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        selectTask?.cancel()
        selectTask = nil
    }

    private func loadSelectedRoom(sessionStore: SessionStore, roomID: Int) async throws {
        async let points = sessionStore.roomMap(roomID: roomID)
        async let occupants = sessionStore.currentOccupants(roomID: roomID)
        async let metrics = sessionStore.roomMetrics(roomID: roomID)
        // Beacons degrade gracefully: a failed beacons fetch never fails the
        // whole radar load; the markers just disappear for that refresh.
        async let beacons = Self.roomBeaconsOrEmpty(sessionStore: sessionStore, roomID: roomID)
        let loaded = try await (points: points, occupants: occupants, metrics: metrics, beacons: beacons)
        // A slower response for a previously selected room must not
        // overwrite the currently selected room's data.
        guard roomID == selectedRoomID else { return }
        self.radarPoints = loaded.points
        self.occupants = loaded.occupants
        self.metrics = loaded.metrics
        self.roomBeacons = loaded.beacons
    }

    private static func roomBeaconsOrEmpty(sessionStore: SessionStore, roomID: Int) async -> [AdminBeacon] {
        do {
            let page = try await sessionStore.adminBeacons(
                assignmentFilter: .assigned,
                roomID: roomID,
                page: 1,
                perPage: 100
            )
            return page.beacons
        } catch {
            return []
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var sessionConfigs = SessionConfigs.empty
    @Published var systemConfig = SystemConfig.empty
    @Published var state: LoadState = .idle
    @Published var saveOutcome: ActionOutcome?
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

    /// The three PUTs run independently and each outcome is reported, so a
    /// mid-sequence failure never silently drops the later requests.
    func save(sessionStore: SessionStore) async {
        isSaving = true
        saveOutcome = nil

        var parts: [String] = []
        var anyFailed = false

        do {
            try await sessionStore.updateSessionConfig(session: "AM", config: sessionConfigs.am)
            parts.append("AM saved")
        } catch {
            anyFailed = true
            parts.append("AM failed: \(readableMessage(for: error))")
        }

        do {
            try await sessionStore.updateSessionConfig(session: "PM", config: sessionConfigs.pm)
            parts.append("PM saved")
        } catch {
            anyFailed = true
            parts.append("PM failed: \(readableMessage(for: error))")
        }

        do {
            try await sessionStore.updateSystemConfig(systemConfig)
            parts.append("System saved")
        } catch {
            anyFailed = true
            parts.append("System failed: \(readableMessage(for: error))")
        }

        if anyFailed {
            saveOutcome = .failure(parts.joined(separator: ", "))
        } else {
            saveOutcome = .success("Settings saved")
        }
        state = .loaded
        isSaving = false
    }
}

@MainActor
final class AdministrationViewModel: ObservableObject {
    @Published var selectedMode: AdministrationMode = .users

    // MARK: Users tab state
    @Published var users: [AdminUser] = []
    @Published var total = 0
    @Published var page = 1
    @Published var perPage = 20
    @Published var searchText = ""
    @Published var roleFilter: AdminUserRoleFilter = .learner
    @Published var sessionFilter: SessionFilter = .all
    @Published var includeInactive = false
    @Published var state: LoadState = .idle
    @Published var actionMessage: ActionOutcome?
    @Published var isSaving = false

    // MARK: Rooms tab state
    @Published var rooms: [Room] = []
    @Published var roomState: LoadState = .idle
    @Published var roomActionMessage: ActionOutcome?
    /// Per-room beacon rollup owned by the Rooms tab. Never written by the
    /// Beacons tab, so switching tabs cannot corrupt the room counts.
    @Published var roomBeaconSummary: [Int: RoomBeaconSummary] = [:]

    // MARK: Beacons tab state (paginated, filtered list slice)
    @Published var beacons: [AdminBeacon] = []
    @Published var beaconState: LoadState = .idle
    @Published var beaconActionMessage: ActionOutcome?
    @Published var beaconSearchText = ""
    @Published var beaconAssignmentFilter: BeaconAssignmentFilter = .all
    @Published var beaconRoomFilterID: Int?
    @Published var beaconTotal = 0
    @Published var beaconPage = 1
    @Published var beaconPerPage = 20

    // One in-flight load per tab slice; a new intent cancels the prior one
    // so a slow, stale response can never overwrite fresher state.
    private var usersLoadTask: Task<Void, Never>?
    private var roomsLoadTask: Task<Void, Never>?
    private var beaconsLoadTask: Task<Void, Never>?

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
        // Always refetch the newly selected tab so it never shows stale data
        // (e.g. after another tab's mutation changed shared backend records).
        switch mode {
        case .users:
            Task { await load(sessionStore: sessionStore) }
        case .rooms:
            Task { await loadRooms(sessionStore: sessionStore) }
        case .beacons:
            Task { await loadBeacons(sessionStore: sessionStore) }
        }
    }

    // MARK: Users tab

    func load(sessionStore: SessionStore) async {
        state = .loading
        await runUsersFetch(sessionStore: sessionStore)
    }

    func applyFilters(sessionStore: SessionStore) async {
        page = 1
        await runUsersFetch(sessionStore: sessionStore)
    }

    func nextPage(sessionStore: SessionStore) async {
        guard canGoNext else { return }
        page += 1
        await runUsersFetch(sessionStore: sessionStore)
    }

    func previousPage(sessionStore: SessionStore) async {
        guard canGoPrevious else { return }
        page -= 1
        await runUsersFetch(sessionStore: sessionStore)
    }

    func save(form: AdminUserForm, sessionStore: SessionStore) async -> ActionOutcome {
        if let message = FormValidators.validate(userForm: form) {
            return .failure(message)
        }
        isSaving = true
        actionMessage = nil
        defer { isSaving = false }
        do {
            let outcome: ActionOutcome
            if let userID = form.userID {
                _ = try await sessionStore.updateAdminUser(id: userID, form: form)
                outcome = .success("User updated")
            } else {
                _ = try await sessionStore.createAdminUser(form)
                outcome = .success("User created")
            }
            actionMessage = outcome
            await runUsersFetch(sessionStore: sessionStore)
            return outcome
        } catch {
            // The sheet shows the failure inline; the list data is still
            // valid, so the background list state must not become .failed.
            return .failure(readableMessage(for: error))
        }
    }

    func resetPassword(user: AdminUser, newPassword: String, sessionStore: SessionStore) async -> ActionOutcome {
        if let message = FormValidators.validatePassword(newPassword) {
            return .failure(message)
        }
        isSaving = true
        actionMessage = nil
        defer { isSaving = false }
        do {
            try await sessionStore.resetAdminUserPassword(id: user.id, newPassword: newPassword)
            let outcome = ActionOutcome.success("Password reset")
            actionMessage = outcome
            return outcome
        } catch {
            return .failure(readableMessage(for: error))
        }
    }

    func delete(user: AdminUser, sessionStore: SessionStore) async {
        isSaving = true
        actionMessage = nil
        do {
            try await sessionStore.deleteAdminUser(id: user.id)
            actionMessage = .success("User deactivated")
            await runUsersFetch(sessionStore: sessionStore)
        } catch {
            actionMessage = .failure(readableMessage(for: error))
        }
        isSaving = false
    }

    func reactivate(user: AdminUser, sessionStore: SessionStore) async {
        isSaving = true
        actionMessage = nil
        do {
            try await sessionStore.reactivateAdminUser(id: user.id)
            actionMessage = .success("User reactivated")
            await runUsersFetch(sessionStore: sessionStore)
        } catch {
            actionMessage = .failure(readableMessage(for: error))
        }
        isSaving = false
    }

    // MARK: Rooms tab

    func loadRooms(sessionStore: SessionStore) async {
        roomState = .loading
        await runRoomsFetch(sessionStore: sessionStore)
    }

    func saveRoom(form: AdminRoomForm, sessionStore: SessionStore) async -> ActionOutcome {
        if let message = FormValidators.validate(roomForm: form) {
            return .failure(message)
        }
        isSaving = true
        roomActionMessage = nil
        defer { isSaving = false }
        do {
            let outcome: ActionOutcome
            if let roomID = form.roomID {
                _ = try await sessionStore.updateRoom(id: roomID, form: form)
                outcome = .success("Room updated")
            } else {
                _ = try await sessionStore.createRoom(form)
                outcome = .success("Room created")
            }
            roomActionMessage = outcome
            await runRoomsFetch(sessionStore: sessionStore)
            return outcome
        } catch {
            return .failure(readableMessage(for: error))
        }
    }

    func delete(room: Room, sessionStore: SessionStore) async {
        isSaving = true
        roomActionMessage = nil
        do {
            try await sessionStore.deleteRoom(id: room.id)
            roomActionMessage = .success("Room deleted")
            await runRoomsFetch(sessionStore: sessionStore)
        } catch {
            roomActionMessage = .failure(readableMessage(for: error))
        }
        isSaving = false
    }

    // MARK: Beacons tab

    func loadBeacons(sessionStore: SessionStore) async {
        beaconState = .loading
        await runBeaconsFetch(sessionStore: sessionStore)
    }

    func applyBeaconFilters(sessionStore: SessionStore) async {
        beaconPage = 1
        await runBeaconsFetch(sessionStore: sessionStore)
    }

    func nextBeaconPage(sessionStore: SessionStore) async {
        guard canGoNextBeaconPage else { return }
        beaconPage += 1
        await runBeaconsFetch(sessionStore: sessionStore)
    }

    func previousBeaconPage(sessionStore: SessionStore) async {
        guard canGoPreviousBeaconPage else { return }
        beaconPage -= 1
        await runBeaconsFetch(sessionStore: sessionStore)
    }

    func saveBeacon(form: AdminBeaconForm, sessionStore: SessionStore) async -> ActionOutcome {
        if let message = FormValidators.validate(beaconForm: form) {
            return .failure(message)
        }
        isSaving = true
        beaconActionMessage = nil
        defer { isSaving = false }
        do {
            let outcome: ActionOutcome
            if let beaconID = form.beaconID {
                _ = try await sessionStore.updateAdminBeacon(id: beaconID, form: form)
                outcome = .success("Beacon updated")
            } else {
                _ = try await sessionStore.createAdminBeacon(form)
                outcome = .success("Beacon registered")
            }
            beaconActionMessage = outcome
            await runBeaconsFetch(sessionStore: sessionStore)
            return outcome
        } catch {
            return .failure(readableMessage(for: error))
        }
    }

    func delete(beacon: AdminBeacon, sessionStore: SessionStore) async {
        isSaving = true
        beaconActionMessage = nil
        do {
            try await sessionStore.deleteAdminBeacon(id: beacon.id)
            beaconActionMessage = .success("Beacon deleted")
            await runBeaconsFetch(sessionStore: sessionStore)
        } catch {
            beaconActionMessage = .failure(readableMessage(for: error))
        }
        isSaving = false
    }

    func beaconCount(for room: Room) -> Int {
        roomBeaconSummary[room.id]?.count ?? 0
    }

    func beaconStatus(for room: Room) -> String {
        beaconCount(for: room) > 0 ? "Active" : "Inactive"
    }

    // MARK: Load task management

    /// Cancels any in-flight users fetch and starts a fresh one, so a slow
    /// response for an old page/filter can never overwrite newer state.
    private func runUsersFetch(sessionStore: SessionStore) async {
        usersLoadTask?.cancel()
        let task = Task { await self.fetchUsers(sessionStore: sessionStore) }
        usersLoadTask = task
        await task.value
    }

    private func runRoomsFetch(sessionStore: SessionStore) async {
        roomsLoadTask?.cancel()
        let task = Task { await self.fetchRoomsAndBeaconSummary(sessionStore: sessionStore) }
        roomsLoadTask = task
        await task.value
    }

    private func runBeaconsFetch(sessionStore: SessionStore) async {
        beaconsLoadTask?.cancel()
        let task = Task { await self.fetchRoomsAndBeacons(sessionStore: sessionStore) }
        beaconsLoadTask = task
        await task.value
    }

    private static func lastValidPage(total: Int, perPage: Int) -> Int {
        let size = max(perPage, 1)
        return max(1, Int((Double(total) / Double(size)).rounded(.up)))
    }

    // MARK: Fetching

    private func fetchUsers(sessionStore: SessionStore) async {
        do {
            var result = try await sessionStore.adminUsers(
                search: FormValidators.sanitizedSearchTerm(searchText),
                roleFilter: roleFilter,
                sessionFilter: sessionFilter,
                includeInactive: includeInactive,
                page: page,
                perPage: perPage
            )
            try Task.checkCancellation()
            // Clamp: after deletes (or a shrunken result set) the current
            // page can fall past the end; refetch at the last valid page.
            let lastPage = Self.lastValidPage(total: result.total, perPage: result.perPage)
            if result.page > lastPage {
                result = try await sessionStore.adminUsers(
                    search: FormValidators.sanitizedSearchTerm(searchText),
                    roleFilter: roleFilter,
                    sessionFilter: sessionFilter,
                    includeInactive: includeInactive,
                    page: lastPage,
                    perPage: perPage
                )
                try Task.checkCancellation()
            }
            users = result.users
            total = result.total
            page = result.page
            perPage = result.perPage
            state = users.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            // Superseded by a newer fetch; let it own the state.
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(readableMessage(for: error))
        }
    }

    /// Rooms tab load: room list plus a full beacon rollup. Writes ONLY the
    /// Rooms tab slice (`rooms`, `roomBeaconSummary`, `roomState`); the
    /// Beacons tab's paginated list is untouched. Pages through beacons in
    /// batches of 100 so counts stay correct past the first page.
    private func fetchRoomsAndBeaconSummary(sessionStore: SessionStore) async {
        do {
            let rooms = try await sessionStore.rooms()
            try Task.checkCancellation()

            var summary: [Int: RoomBeaconSummary] = [:]
            var accumulated = 0
            var expectedTotal = Int.max
            var pageIndex = 1
            while accumulated < expectedTotal {
                let batch = try await sessionStore.adminBeacons(
                    assignmentFilter: .all,
                    roomID: nil,
                    page: pageIndex,
                    perPage: 100
                )
                try Task.checkCancellation()
                expectedTotal = batch.total
                accumulated += batch.beacons.count
                for beacon in batch.beacons {
                    guard let roomID = beacon.roomID else { continue }
                    summary[roomID, default: RoomBeaconSummary(count: 0)].count += 1
                }
                // Defensive: an empty page means the backend has no more
                // rows even if `total` disagrees; avoid looping forever.
                if batch.beacons.isEmpty { break }
                pageIndex += 1
            }

            self.rooms = rooms
            self.roomBeaconSummary = summary
            roomState = rooms.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            // Superseded by a newer fetch; let it own the state.
        } catch {
            guard !Task.isCancelled else { return }
            roomState = .failed(readableMessage(for: error))
        }
    }

    private func fetchRoomsAndBeacons(sessionStore: SessionStore) async {
        do {
            async let roomsRequest = sessionStore.rooms()
            async let beaconsRequest = sessionStore.adminBeacons(
                assignmentFilter: beaconAssignmentFilter,
                roomID: beaconRoomFilterID,
                page: beaconPage,
                perPage: beaconPerPage
            )
            let rooms = try await roomsRequest
            var result = try await beaconsRequest
            try Task.checkCancellation()
            let lastPage = Self.lastValidPage(total: result.total, perPage: result.perPage)
            if result.page > lastPage {
                result = try await sessionStore.adminBeacons(
                    assignmentFilter: beaconAssignmentFilter,
                    roomID: beaconRoomFilterID,
                    page: lastPage,
                    perPage: beaconPerPage
                )
                try Task.checkCancellation()
            }
            self.rooms = rooms
            self.beacons = result.beacons
            self.beaconTotal = result.total
            self.beaconPage = result.page
            self.beaconPerPage = result.perPage
            beaconState = self.beacons.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            // Superseded by a newer fetch; let it own the state.
        } catch {
            guard !Task.isCancelled else { return }
            beaconState = .failed(readableMessage(for: error))
        }
    }
}

@MainActor
final class ReportsViewModel: ObservableObject {
    /// When false the backend defaults to "yesterday" in its own timezone.
    @Published var useCustomDate = false
    @Published var rollupDate = Date()
    @Published var dateText = ""
    @Published var userIDText = ""
    @Published var result: RollupResult?
    @Published var state: LoadState = .idle
    @Published var isRunning = false
    @Published var message: String?

    // MARK: Attendance report state
    @Published var reportFromDate = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @Published var reportToDate = Date()
    @Published var reportSessionFilter: SessionFilter = .all
    @Published var report: AttendanceReport?
    @Published var reportState: LoadState = .idle
    @Published var isGeneratingReport = false
    @Published var isDownloadingCSV = false
    @Published var reportOutcome: ActionOutcome?

    /// Backend caps the report range at 92 days.
    static let maxReportRangeDays = 92

    private static let rollupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var reportFromString: String {
        Self.rollupDateFormatter.string(from: reportFromDate)
    }

    var reportToString: String {
        Self.rollupDateFormatter.string(from: reportToDate)
    }

    var suggestedCSVFilename: String {
        "aegis-attendance-\(reportFromString)-\(reportToString).csv"
    }

    var suggestedPDFFilename: String {
        "aegis-attendance-\(reportFromString)-\(reportToString).pdf"
    }

    /// Mirrors the backend zod validation: from <= to and range <= 92 days.
    /// Returns nil when valid.
    func validateReportRange() -> String? {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: reportFromDate)
        let to = calendar.startOfDay(for: reportToDate)
        if from > to {
            return "The start date must be on or before the end date."
        }
        let days = (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
        if days > Self.maxReportRangeDays {
            return "The date range must not exceed \(Self.maxReportRangeDays) days."
        }
        return nil
    }

    func generateReport(sessionStore: SessionStore) async {
        if let validationMessage = validateReportRange() {
            reportOutcome = .failure(validationMessage)
            return
        }
        isGeneratingReport = true
        reportOutcome = nil
        reportState = .loading
        do {
            let output = try await sessionStore.attendanceReport(
                from: reportFromString,
                to: reportToString,
                session: reportSessionFilter
            )
            report = output
            reportState = output.perLearner.isEmpty ? .empty : .loaded
        } catch {
            reportState = .failed(readableMessage(for: error))
        }
        isGeneratingReport = false
    }

    /// Fetches the CSV bytes; the view handles the NSSavePanel + disk write.
    func downloadCSVData(sessionStore: SessionStore) async -> Data? {
        if let validationMessage = validateReportRange() {
            reportOutcome = .failure(validationMessage)
            return nil
        }
        isDownloadingCSV = true
        reportOutcome = nil
        defer { isDownloadingCSV = false }
        do {
            return try await sessionStore.attendanceReportCSV(
                from: reportFromString,
                to: reportToString,
                session: reportSessionFilter
            )
        } catch {
            reportOutcome = .failure(readableMessage(for: error))
            return nil
        }
    }

    func runRollup(sessionStore: SessionStore) async {
        isRunning = true
        message = nil
        result = nil
        do {
            if let validationMessage = FormValidators.validateOptionalUserID(userIDText) {
                message = validationMessage
                state = .failed(validationMessage)
                isRunning = false
                return
            }
            let trimmedUserID = userIDText.trimmingCharacters(in: .whitespacesAndNewlines)
            let userID = trimmedUserID.isEmpty ? nil : Int(trimmedUserID)
            let dateString = useCustomDate ? Self.rollupDateFormatter.string(from: rollupDate) : nil
            let output = try await sessionStore.runRollup(
                date: dateString,
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
