import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdministrationView: View {
    @ObservedObject var viewModel: AdministrationViewModel
    @ObservedObject var sessionStore: SessionStore
    let currentAdminID: Int

    @State private var userForm: AdminUserForm?
    @State private var passwordResetUser: AdminUser?
    @State private var deleteTarget: AdminUser?
    @State private var reactivateTarget: AdminUser?
    @State private var roomForm: AdminRoomForm?
    @State private var roomDeleteTarget: Room?
    @State private var beaconForm: AdminBeaconForm?
    @State private var beaconDeleteTarget: AdminBeacon?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Administration")
                    .screenTitle()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(AdministrationMode.allCases) { mode in
                            AdminModePill(
                                title: mode.rawValue,
                                isSelected: viewModel.selectedMode == mode
                            ) {
                                viewModel.selectMode(mode, sessionStore: sessionStore)
                            }
                        }
                    }
                }

                activeAdministrationPanel

                Spacer(minLength: 0)
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if viewModel.state == .idle {
                await viewModel.load(sessionStore: sessionStore)
            }
        }
        .sheet(item: $userForm) { form in
            AdminUserFormSheet(form: form, isSaving: viewModel.isSaving) { draft in
                await viewModel.save(form: draft, sessionStore: sessionStore)
            }
        }
        .sheet(item: $passwordResetUser) { user in
            PasswordResetSheet(user: user, isSaving: viewModel.isSaving) { password in
                await viewModel.resetPassword(user: user, newPassword: password, sessionStore: sessionStore)
            }
        }
        .sheet(item: $roomForm) { form in
            AdminRoomFormSheet(form: form, isSaving: viewModel.isSaving) { draft in
                await viewModel.saveRoom(form: draft, sessionStore: sessionStore)
            }
        }
        .sheet(item: $beaconForm) { form in
            AdminBeaconFormSheet(form: form, rooms: viewModel.rooms, isSaving: viewModel.isSaving) { draft in
                await viewModel.saveBeacon(form: draft, sessionStore: sessionStore)
            }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            // Backend rejects search terms over 100 chars with a 400; clamp
            // the field so the list request can never trip that limit.
            if newValue.count > FormValidators.searchMaxLength {
                viewModel.searchText = String(newValue.prefix(FormValidators.searchMaxLength))
            }
        }
        .alert(
            "Deactivate User?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { user in
            Button("Deactivate", role: .destructive) {
                Task {
                    await viewModel.delete(user: user, sessionStore: sessionStore)
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: { user in
            Text(user.displayName)
        }
        .alert(
            "Reactivate User?",
            isPresented: Binding(
                get: { reactivateTarget != nil },
                set: { if !$0 { reactivateTarget = nil } }
            ),
            presenting: reactivateTarget
        ) { user in
            Button("Reactivate") {
                Task {
                    await viewModel.reactivate(user: user, sessionStore: sessionStore)
                    reactivateTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                reactivateTarget = nil
            }
        } message: { user in
            Text("Reactivating \(user.displayName) restores the user's access.")
        }
        .alert(
            "Delete Room?",
            isPresented: Binding(
                get: { roomDeleteTarget != nil },
                set: { if !$0 { roomDeleteTarget = nil } }
            ),
            presenting: roomDeleteTarget
        ) { room in
            Button("Delete Room", role: .destructive) {
                Task {
                    await viewModel.delete(room: room, sessionStore: sessionStore)
                    roomDeleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                roomDeleteTarget = nil
            }
        } message: { room in
            Text("This will delete \(room.name). Rooms with recorded presence cannot be deleted by the backend.")
        }
        .alert(
            "Delete Beacon?",
            isPresented: Binding(
                get: { beaconDeleteTarget != nil },
                set: { if !$0 { beaconDeleteTarget = nil } }
            ),
            presenting: beaconDeleteTarget
        ) { beacon in
            Button("Delete Beacon", role: .destructive) {
                Task {
                    await viewModel.delete(beacon: beacon, sessionStore: sessionStore)
                    beaconDeleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                beaconDeleteTarget = nil
            }
        } message: { beacon in
            Text(beacon.name)
        }
    }

    @ViewBuilder
    private var activeAdministrationPanel: some View {
        switch viewModel.selectedMode {
        case .users:
            usersPanel
        case .rooms:
            roomsPanel
        case .beacons:
            beaconsPanel
        }
    }

    private var usersPanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 16) {
                AdministrationToolbar(
                    searchText: $viewModel.searchText,
                    roleFilter: $viewModel.roleFilter,
                    sessionFilter: $viewModel.sessionFilter,
                    includeInactive: $viewModel.includeInactive,
                    applyFilters: {
                        Task { await viewModel.applyFilters(sessionStore: sessionStore) }
                    },
                    addUser: {
                        userForm = AdminUserForm()
                    }
                )

                AdaptiveHorizontalTable(
                    minWidth: 900,
                    rowCount: viewModel.users.count,
                    state: viewModel.state
                ) {
                    AdminUsersTable(
                        rows: viewModel.users,
                        state: viewModel.state,
                        currentAdminID: currentAdminID,
                        edit: { userForm = AdminUserForm(user: $0) },
                        resetPassword: { passwordResetUser = $0 },
                        delete: { deleteTarget = $0 },
                        reactivate: { reactivateTarget = $0 },
                        retry: {
                            Task { await viewModel.load(sessionStore: sessionStore) }
                        }
                    )
                }

                AdminPaginationFooter(
                    summary: viewModel.pageSummary,
                    outcome: viewModel.actionMessage,
                    canGoPrevious: viewModel.canGoPrevious,
                    canGoNext: viewModel.canGoNext,
                    previous: {
                        Task { await viewModel.previousPage(sessionStore: sessionStore) }
                    },
                    next: {
                        Task { await viewModel.nextPage(sessionStore: sessionStore) }
                    }
                )
            }
        }
    }

    private var roomsPanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 16) {
                RoomManagementToolbar {
                    roomForm = AdminRoomForm()
                }

                AdaptiveHorizontalTable(
                    minWidth: 720,
                    rowCount: viewModel.rooms.count,
                    state: viewModel.roomState
                ) {
                    AdminRoomsTable(
                        rows: viewModel.rooms,
                        state: viewModel.roomState,
                        beaconCount: { viewModel.beaconCount(for: $0) },
                        beaconStatus: { viewModel.beaconStatus(for: $0) },
                        edit: { roomForm = AdminRoomForm(room: $0) },
                        delete: { roomDeleteTarget = $0 },
                        retry: {
                            Task { await viewModel.loadRooms(sessionStore: sessionStore) }
                        }
                    )
                }

                AdminPaginationFooter(
                    summary: "Showing \(viewModel.rooms.count) rooms",
                    outcome: viewModel.roomActionMessage,
                    canGoPrevious: false,
                    canGoNext: false,
                    previous: {},
                    next: {}
                )
            }
        }
    }

    private var beaconsPanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 16) {
                BeaconManagementToolbar(
                    searchText: $viewModel.beaconSearchText,
                    assignmentFilter: $viewModel.beaconAssignmentFilter,
                    roomFilterID: $viewModel.beaconRoomFilterID,
                    rooms: viewModel.rooms,
                    applyFilters: {
                        Task { await viewModel.applyBeaconFilters(sessionStore: sessionStore) }
                    },
                    addBeacon: {
                        beaconForm = AdminBeaconForm()
                    }
                )

                AdaptiveHorizontalTable(
                    minWidth: 820,
                    rowCount: viewModel.filteredBeacons.count,
                    state: viewModel.beaconState
                ) {
                    AdminBeaconsTable(
                        rows: viewModel.filteredBeacons,
                        state: viewModel.beaconState,
                        edit: { beaconForm = AdminBeaconForm(beacon: $0) },
                        delete: { beaconDeleteTarget = $0 },
                        retry: {
                            Task { await viewModel.loadBeacons(sessionStore: sessionStore) }
                        }
                    )
                }

                AdminPaginationFooter(
                    summary: viewModel.beaconPageSummary,
                    outcome: viewModel.beaconActionMessage,
                    canGoPrevious: viewModel.canGoPreviousBeaconPage,
                    canGoNext: viewModel.canGoNextBeaconPage,
                    previous: {
                        Task { await viewModel.previousBeaconPage(sessionStore: sessionStore) }
                    },
                    next: {
                        Task { await viewModel.nextBeaconPage(sessionStore: sessionStore) }
                    }
                )
            }
        }
    }
}

private struct AdministrationToolbar: View {
    @Binding var searchText: String
    @Binding var roleFilter: AdminUserRoleFilter
    @Binding var sessionFilter: SessionFilter
    @Binding var includeInactive: Bool
    let applyFilters: () -> Void
    let addUser: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("User Management", systemImage: "person.3.fill")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button(action: addUser) {
                    Label("Add New User", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(AegisColors.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    SearchField(text: $searchText, placeholder: "Search by Name...")
                        .frame(width: 220)
                        .onSubmit {
                            applyFilters()
                        }

                    Picker("Role", selection: $roleFilter) {
                        ForEach(AdminUserRoleFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Picker("Session", selection: $sessionFilter) {
                        ForEach(SessionFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)

                    Toggle("Inactive", isOn: $includeInactive)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .semibold))

                    Button(action: applyFilters) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AegisColors.teal)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .help("Apply filters")
                }
                .padding(.bottom, 1)
            }
        }
    }
}

private struct RoomManagementToolbar: View {
    let addRoom: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Room Management", systemImage: "building.2.fill")
                .font(.system(size: 16, weight: .bold))

            Spacer()

            Button(action: addRoom) {
                Label("Add New Room", systemImage: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(AegisColors.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct BeaconManagementToolbar: View {
    @Binding var searchText: String
    @Binding var assignmentFilter: BeaconAssignmentFilter
    @Binding var roomFilterID: Int?
    let rooms: [Room]
    let applyFilters: () -> Void
    let addBeacon: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("Beacon Management", systemImage: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button(action: addBeacon) {
                    Label("Register New Beacon", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(AegisColors.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    SearchField(text: $searchText, placeholder: "Search...")
                        .frame(width: 220)

                    Picker("Assignment", selection: $assignmentFilter) {
                        ForEach(BeaconAssignmentFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 136)

                    Picker("Room", selection: $roomFilterID) {
                        Text("All Rooms").tag(Optional<Int>.none)
                        ForEach(rooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)

                    Button(action: applyFilters) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AegisColors.teal)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .help("Apply filters")
                }
                .padding(.bottom, 1)
            }
        }
    }
}

/// Shared pagination footer used by the Administration tabs and the
/// Dashboard attendance table.
struct AdminPaginationFooter: View {
    let summary: String
    let outcome: ActionOutcome?
    let canGoPrevious: Bool
    let canGoNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AegisColors.mutedText)

            if let outcome {
                Text(outcome.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(outcome.isSuccess ? AegisColors.activeGreen : Color.red)
            }

            Spacer()

            Button {
                previous()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoPrevious)
            .help("Previous page")

            Button {
                next()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoNext)
            .help("Next page")
        }
    }
}

/// Error banner with a Retry action so a failed tab is never a dead end.
private struct RetryableErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ErrorBanner(message: message)

            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(AegisColors.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Try loading again")
        }
    }
}

private struct AdaptiveHorizontalTable<Content: View>: View {
    let minWidth: CGFloat
    let rowCount: Int
    let state: LoadState
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                content
                    .frame(width: max(minWidth, proxy.size.width), alignment: .leading)
            }
        }
        .frame(height: estimatedHeight)
    }

    private var estimatedHeight: CGFloat {
        let bodyHeight: CGFloat
        if case .loading = state {
            bodyHeight = 120
        } else if rowCount == 0 {
            bodyHeight = 120
        } else {
            bodyHeight = CGFloat(rowCount) * 48
        }

        let errorHeight: CGFloat
        if case .failed = state {
            errorHeight = 56
        } else {
            errorHeight = 0
        }

        return 42 + bodyHeight + errorHeight
    }
}

private struct AdminModePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : AegisColors.teal)
                .frame(width: 138, height: 30)
                .background(isSelected ? AegisColors.teal : Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AdminRoomsTable: View {
    let rows: [Room]
    let state: LoadState
    let beaconCount: (Room) -> Int
    let beaconStatus: (Room) -> String
    let edit: (Room) -> Void
    let delete: (Room) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Room Name", .infinity),
                ("Beacon Count", 132),
                ("Beacon Status", 150),
                ("Actions", 110)
            ])

            if case .loading = state {
                TableMessage("Loading rooms...")
            } else if rows.isEmpty {
                TableMessage("No rooms found.")
            } else {
                ForEach(rows) { room in
                    HStack(spacing: 0) {
                        Text(room.name).tableCell(maxWidth: .infinity, alignment: .leading)
                        Text("\(beaconCount(room))").tableCell(width: 132)
                        Text(beaconStatus(room))
                            .foregroundStyle(beaconCount(room) > 0 ? AegisColors.activeGreen : AegisColors.mutedText)
                            .tableCell(width: 150)

                        HStack(spacing: 8) {
                            IconActionButton(symbol: "pencil", tint: Color.blue) {
                                edit(room)
                            }
                            .help("Edit room")

                            IconActionButton(symbol: "trash", tint: Color.red) {
                                delete(room)
                            }
                            .help("Delete room")
                        }
                        .frame(width: 110)
                    }
                    .frame(height: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                }
            }

            if case let .failed(message) = state {
                RetryableErrorBanner(message: message, retry: retry)
                    .padding(.top, 12)
            }
        }
    }
}

private struct AdminBeaconsTable: View {
    let rows: [AdminBeacon]
    let state: LoadState
    let edit: (AdminBeacon) -> Void
    let delete: (AdminBeacon) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Beacon Name", .infinity),
                ("Identifier", 160),
                ("Assigned Room", 180),
                ("Status", 118),
                ("Actions", 110)
            ])

            if case .loading = state {
                TableMessage("Loading beacons...")
            } else if rows.isEmpty {
                TableMessage("No beacons found.")
            } else {
                ForEach(rows) { beacon in
                    HStack(spacing: 0) {
                        Text(beacon.name).tableCell(maxWidth: .infinity, alignment: .leading)
                        Text(beacon.beaconIdentifier).tableCell(width: 160, alignment: .leading)
                        Text(beacon.assignmentText).tableCell(width: 180, alignment: .leading)
                        Text(beacon.statusText)
                            .foregroundStyle(beacon.roomID == nil ? AegisColors.mutedText : AegisColors.activeGreen)
                            .tableCell(width: 118)

                        HStack(spacing: 8) {
                            IconActionButton(symbol: "pencil", tint: Color.blue) {
                                edit(beacon)
                            }
                            .help("Edit beacon")

                            IconActionButton(symbol: "trash", tint: Color.red) {
                                delete(beacon)
                            }
                            .help("Delete beacon")
                        }
                        .frame(width: 110)
                    }
                    .frame(height: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                }
            }

            if case let .failed(message) = state {
                RetryableErrorBanner(message: message, retry: retry)
                    .padding(.top, 12)
            }
        }
    }
}

private struct AdminUsersTable: View {
    let rows: [AdminUser]
    let state: LoadState
    let currentAdminID: Int
    let edit: (AdminUser) -> Void
    let resetPassword: (AdminUser) -> Void
    let delete: (AdminUser) -> Void
    let reactivate: (AdminUser) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Name", .infinity),
                ("Role", 92),
                ("Session", 92),
                ("Email", 220),
                ("Status", 92),
                ("Actions", 142)
            ])

            if case .loading = state {
                TableMessage("Loading users...")
            } else if rows.isEmpty {
                TableMessage("No users found.")
            } else {
                ForEach(rows) { user in
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            Text("@\(user.username)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AegisColors.mutedText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13)

                        Text(user.role.title).tableCell(width: 92)
                        Text(user.sessionDisplay).tableCell(width: 92)
                        Text(user.email).tableCell(width: 220, alignment: .leading)
                        Text(user.statusText)
                            .foregroundStyle(user.isActive ? AegisColors.activeGreen : AegisColors.mutedText)
                            .tableCell(width: 92)

                        HStack(spacing: 8) {
                            IconActionButton(symbol: "pencil", tint: Color.blue) {
                                edit(user)
                            }
                            .help("Edit user")

                            IconActionButton(symbol: "key", tint: AegisColors.teal) {
                                resetPassword(user)
                            }
                            .help("Reset password")

                            if user.isActive {
                                IconActionButton(symbol: "trash", tint: Color.red) {
                                    delete(user)
                                }
                                .disabled(user.id == currentAdminID)
                                .opacity(user.id == currentAdminID ? 0.35 : 1)
                                .help(user.id == currentAdminID ? "Cannot deactivate yourself" : "Deactivate user")
                            } else {
                                IconActionButton(symbol: "arrow.counterclockwise", tint: AegisColors.activeGreen) {
                                    reactivate(user)
                                }
                                .help("Reactivate user")
                            }
                        }
                        .frame(width: 142)
                    }
                    .frame(height: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                }
            }

            if case let .failed(message) = state {
                RetryableErrorBanner(message: message, retry: retry)
                    .padding(.top, 12)
            }
        }
    }
}

private struct IconActionButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AdminUserFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AdminUserForm
    @State private var errorText: String?
    let isSaving: Bool
    let onSave: (AdminUserForm) async -> ActionOutcome

    init(form: AdminUserForm, isSaving: Bool, onSave: @escaping (AdminUserForm) async -> ActionOutcome) {
        self._draft = State(initialValue: form)
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.title)
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text("User Details")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AegisColors.teal)

                HStack(spacing: 14) {
                    FormTextField(title: "Username", text: $draft.username)
                        .disabled(draft.isEditing)
                    Picker("Role", selection: $draft.role) {
                        ForEach(AdminUserRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                HStack(spacing: 14) {
                    FormTextField(title: "First Name", text: $draft.firstName)
                    FormTextField(title: "Last Name", text: $draft.lastName)
                }

                HStack(spacing: 14) {
                    FormTextField(title: "Email", text: $draft.email)
                    Picker("Session", selection: $draft.session) {
                        Text("AM").tag("AM")
                        Text("PM").tag("PM")
                    }
                    .disabled(draft.role == .admin)
                    .frame(width: 170)
                }

                if !draft.isEditing {
                    SecureFormField(title: "Password", text: $draft.password)
                }

                if let errorText {
                    SheetErrorText(message: errorText)
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(draft.submitTitle) {
                    Task {
                        switch await onSave(draft) {
                        case .success:
                            errorText = nil
                            dismiss()
                        case let .failure(message):
                            errorText = message
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSubmit || isSaving)
            }
            .padding(16)
        }
        .frame(width: 560, height: (draft.isEditing ? 390 : 455) + (errorText == nil ? 0 : 40))
    }
}

private struct PasswordResetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorText: String?
    let user: AdminUser
    let isSaving: Bool
    let onSave: (String) async -> ActionOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reset Password")
                .font(.system(size: 18, weight: .bold))
            Text(user.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AegisColors.mutedText)
            SecureFormField(title: "New Password", text: $password)

            if let errorText {
                SheetErrorText(message: errorText)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Reset Password") {
                    Task {
                        switch await onSave(password) {
                        case .success:
                            errorText = nil
                            dismiss()
                        case let .failure(message):
                            errorText = message
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct AdminRoomFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AdminRoomForm
    @State private var errorText: String?
    let isSaving: Bool
    let onSave: (AdminRoomForm) async -> ActionOutcome

    init(form: AdminRoomForm, isSaving: Bool, onSave: @escaping (AdminRoomForm) async -> ActionOutcome) {
        self._draft = State(initialValue: form)
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.title)
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text("Room Details")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AegisColors.teal)

                FormTextField(title: "Room Name", text: $draft.name)

                if let errorText {
                    SheetErrorText(message: errorText)
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()

            HStack {
                if draft.isEditing {
                    Text("Deleting is available from the room table.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AegisColors.mutedText)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(draft.submitTitle) {
                    Task {
                        switch await onSave(draft) {
                        case .success:
                            errorText = nil
                            dismiss()
                        case let .failure(message):
                            errorText = message
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSubmit || isSaving)
            }
            .padding(16)
        }
        .frame(width: 460, height: 260 + (errorText == nil ? 0 : 40))
    }
}

private struct AdminBeaconFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AdminBeaconForm
    @State private var errorText: String?
    let rooms: [Room]
    let isSaving: Bool
    let onSave: (AdminBeaconForm) async -> ActionOutcome

    init(form: AdminBeaconForm, rooms: [Room], isSaving: Bool, onSave: @escaping (AdminBeaconForm) async -> ActionOutcome) {
        self._draft = State(initialValue: form)
        self.rooms = rooms
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.title)
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text("Beacon Details")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AegisColors.teal)

                HStack(spacing: 14) {
                    FormTextField(title: "Beacon Name", text: $draft.name)
                    FormTextField(title: "Beacon ID / Serial Number", text: $draft.beaconIdentifier)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Assigned Room")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AegisColors.mutedText)
                    Picker("Assigned Room", selection: $draft.roomID) {
                        Text("Unassigned").tag(Optional<Int>.none)
                        ForEach(rooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                HStack(spacing: 14) {
                    FormTextField(title: "Position X (0\u{2013}1)", text: $draft.positionXText)
                    FormTextField(title: "Position Y (0\u{2013}1)", text: $draft.positionYText)
                }

                Text("Positions are normalized to the room: (0, 0) is top-left, (1, 1) is bottom-right. Leave empty to clear the beacon's position.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AegisColors.mutedText)

                if let errorText {
                    SheetErrorText(message: errorText)
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()

            HStack {
                if draft.isEditing {
                    Text("Set room to Unassigned to detach this beacon.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AegisColors.mutedText)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(draft.submitTitle) {
                    Task {
                        switch await onSave(draft) {
                        case .success:
                            errorText = nil
                            dismiss()
                        case let .failure(message):
                            errorText = message
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSubmit || isSaving)
            }
            .padding(16)
        }
        .frame(width: 620, height: 445 + (errorText == nil ? 0 : 40))
    }
}

/// Inline validation/save error shown inside a form sheet, so the sheet can
/// stay open with the user's input intact.
private struct SheetErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AegisColors.mutedText)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct SecureFormField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AegisColors.mutedText)
            SecureField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct ReportsView: View {
    @ObservedObject var viewModel: ReportsViewModel
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Reports")
                    .screenTitle()

                attendanceReportPanel

                rollupPanel

                Spacer(minLength: 0)
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Attendance report

    private var attendanceReportPanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 20) {
                Label("Attendance Report", systemImage: "chart.bar.doc.horizontal")
                    .font(.system(size: 16, weight: .bold))

                reportControls

                if let report = viewModel.report {
                    reportSummaryCards(report)
                    ReportLearnersTable(rows: report.perLearner, state: viewModel.reportState)
                    Text("\(report.from) to \(report.to) \u{2022} \(report.daysWithSessions) days with sessions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AegisColors.mutedText)
                } else if case .loading = viewModel.reportState {
                    TableMessage("Generating report...")
                } else if case .empty = viewModel.reportState {
                    TableMessage("No attendance data in the selected range.")
                }

                if let outcome = viewModel.reportOutcome {
                    Text(outcome.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(outcome.isSuccess ? AegisColors.activeGreen : Color.red)
                }

                if case let .failed(message) = viewModel.reportState {
                    ErrorBanner(message: message)
                }
            }
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var reportControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                reportRangeFields
                reportActionButtons
            }

            VStack(alignment: .leading, spacing: 14) {
                reportRangeFields
                reportActionButtons
            }
        }
    }

    private var reportRangeFields: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("From")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AegisColors.mutedText)
                DatePicker("From", selection: $viewModel.reportFromDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("To")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AegisColors.mutedText)
                DatePicker("To", selection: $viewModel.reportToDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Session")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AegisColors.mutedText)
                Picker("Session", selection: $viewModel.reportSessionFilter) {
                    ForEach(SessionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }
    }

    private var reportActionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.generateReport(sessionStore: sessionStore) }
            } label: {
                Label(viewModel.isGeneratingReport ? "Generating..." : "Generate", systemImage: "chart.bar.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(AegisColors.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGeneratingReport || viewModel.isDownloadingCSV)

            Button {
                Task { await downloadCSV() }
            } label: {
                Label(viewModel.isDownloadingCSV ? "Downloading..." : "Download CSV", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AegisColors.teal)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(AegisColors.teal, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGeneratingReport || viewModel.isDownloadingCSV)
        }
    }

    private func reportSummaryCards(_ report: AttendanceReport) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                reportMetrics(report)
            }
            VStack(alignment: .leading, spacing: 12) {
                reportMetrics(report)
            }
        }
    }

    @ViewBuilder
    private func reportMetrics(_ report: AttendanceReport) -> some View {
        RollupMetric(title: "Attendance Rate", value: formatRatePercent(report.summary.attendanceRate))
        RollupMetric(title: "Learners", value: "\(report.summary.learners)")
        RollupMetric(title: "Total Late", value: "\(report.summary.totalLate)")
        RollupMetric(title: "Total Absent", value: "\(report.summary.totalAbsent)")
    }

    private func downloadCSV() async {
        guard let data = await viewModel.downloadCSVData(sessionStore: sessionStore) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = viewModel.suggestedCSVFilename
        panel.canCreateDirectories = true
        if let csvType = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csvType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            viewModel.reportOutcome = .success("CSV saved to \(url.lastPathComponent)")
        } catch {
            viewModel.reportOutcome = .failure("Could not save the CSV: \(error.localizedDescription)")
        }
    }

    // MARK: Rollup (secondary action)

    private var rollupPanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 20) {
                Label("Generate Attendance Rollup", systemImage: "doc.text.fill")
                    .font(.system(size: 16, weight: .bold))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        reportFields
                        reportResult
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        reportFields
                        reportResult
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await viewModel.runRollup(sessionStore: sessionStore) }
                    } label: {
                        Label(viewModel.isRunning ? "Running..." : "Run Rollup", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(AegisColors.teal)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRunning)
                }

                if case let .failed(message) = viewModel.state {
                    ErrorBanner(message: message)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var reportFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Specific Date", isOn: $viewModel.useCustomDate)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AegisColors.mutedText)

                if viewModel.useCustomDate {
                    DatePicker(
                        "Date",
                        selection: $viewModel.rollupDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                } else {
                    Text("Defaults to yesterday")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AegisColors.mutedText)
                }
            }
            .frame(width: 190, alignment: .leading)

            FormTextField(title: "User ID", text: $viewModel.userIDText)
                .frame(width: 190)
        }
    }

    private var reportResult: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    RollupMetric(title: "Processed", value: "\(viewModel.result?.processed ?? 0)")
                    RollupMetric(title: "Leave Skipped", value: "\(viewModel.result?.skippedLeave ?? 0)")
                }

                VStack(alignment: .leading, spacing: 12) {
                    RollupMetric(title: "Processed", value: "\(viewModel.result?.processed ?? 0)")
                    RollupMetric(title: "Leave Skipped", value: "\(viewModel.result?.skippedLeave ?? 0)")
                }
            }

            if let message = viewModel.message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(message == "Rollup completed" ? AegisColors.activeGreen : Color.red)
            }
        }
    }
}

private struct ReportLearnersTable: View {
    let rows: [AttendanceReportLearner]
    let state: LoadState

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Learner", .infinity),
                ("Session", 90),
                ("Present", 90),
                ("Late", 80),
                ("Absent", 90),
                ("Rate", 90)
            ])

            if rows.isEmpty {
                TableMessage("No learners in the selected range.")
            } else {
                ForEach(rows) { learner in
                    HStack(spacing: 0) {
                        Text(learner.name).tableCell(maxWidth: .infinity, alignment: .leading)
                        Text(learner.session).tableCell(width: 90)
                        Text("\(learner.present)").tableCell(width: 90)
                        Text("\(learner.late)")
                            .foregroundStyle(learner.late > 0 ? AegisColors.inactiveYellow : .black)
                            .tableCell(width: 80)
                        Text("\(learner.absent)")
                            .foregroundStyle(learner.absent > 0 ? Color.red : .black)
                            .tableCell(width: 90)
                        Text(formatRatePercent(learner.attendanceRate)).tableCell(width: 90)
                    }
                    .frame(height: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct RollupMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AegisColors.mutedText)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
        }
        .padding(16)
        .frame(width: 150, alignment: .leading)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}
