import SwiftUI

struct AdministrationView: View {
    @ObservedObject var viewModel: AdministrationViewModel
    @ObservedObject var sessionStore: SessionStore
    let currentAdminID: Int

    @State private var userForm: AdminUserForm?
    @State private var passwordResetUser: AdminUser?
    @State private var deleteTarget: AdminUser?
    @State private var roomForm: AdminRoomForm?
    @State private var roomDeleteTarget: Room?
    @State private var beaconForm: AdminBeaconForm?
    @State private var beaconDeleteTarget: AdminBeacon?

    var body: some View {
        administrationContent
            .task {
                await loadIfNeeded()
            }
            .modifier(AdministrationSheets(
                userForm: $userForm,
                passwordResetUser: $passwordResetUser,
                deleteTarget: $deleteTarget,
                roomForm: $roomForm,
                roomDeleteTarget: $roomDeleteTarget,
                beaconForm: $beaconForm,
                viewModel: viewModel,
                sessionStore: sessionStore
            ))
            .modifier(AdministrationAlerts(
                deleteTarget: $deleteTarget,
                roomDeleteTarget: $roomDeleteTarget,
                beaconDeleteTarget: $beaconDeleteTarget,
                viewModel: viewModel,
                sessionStore: sessionStore
            ))
    }

    private var administrationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Administration")
                    .screenTitle()

                activeAdministrationPanel

                Spacer(minLength: 0)
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
    }

    private func loadIfNeeded() async {
        if viewModel.state == .idle {
            await viewModel.load(sessionStore: sessionStore)
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
                    applyFilters: {
                        Task { await viewModel.applyFilters(sessionStore: sessionStore) }
                    },
                    addUser: {
                        userForm = AdminUserForm()
                    }
                )

                AdaptiveHorizontalTable(
                    minWidth: 760,
                    rowCount: viewModel.users.count,
                    state: viewModel.state
                ) {
                    AdminUsersTable(
                        rows: viewModel.users,
                        state: viewModel.state,
                        edit: { userForm = AdminUserForm(user: $0) }
                    )
                }

                AdminPaginationFooter(
                    summary: viewModel.pageSummary,
                    message: viewModel.actionMessage,
                    successWords: ["User", "Password"],
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
                        delete: { roomDeleteTarget = $0 }
                    )
                }

                AdminPaginationFooter(
                    summary: "Showing \(viewModel.rooms.count) rooms",
                    message: viewModel.roomActionMessage,
                    successWords: ["Room"],
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
                        delete: { beaconDeleteTarget = $0 }
                    )
                }

                AdminPaginationFooter(
                    summary: viewModel.beaconPageSummary,
                    message: viewModel.beaconActionMessage,
                    successWords: ["Beacon"],
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

private struct AdministrationSheets: ViewModifier {
    @Binding var userForm: AdminUserForm?
    @Binding var passwordResetUser: AdminUser?
    @Binding var deleteTarget: AdminUser?
    @Binding var roomForm: AdminRoomForm?
    @Binding var roomDeleteTarget: Room?
    @Binding var beaconForm: AdminBeaconForm?
    @ObservedObject var viewModel: AdministrationViewModel
    @ObservedObject var sessionStore: SessionStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $userForm) { form in
                AdminUserFormSheet(
                    form: form,
                    isSaving: viewModel.isSaving,
                    onSave: { draft in
                        await viewModel.save(form: draft, sessionStore: sessionStore)
                    },
                    onDelete: {
                        deleteTarget = viewModel.users.first { $0.id == form.userID }
                    }
                )
            }
            .sheet(item: $passwordResetUser) { user in
                PasswordResetSheet(user: user, isSaving: viewModel.isSaving) { password in
                    await viewModel.resetPassword(user: user, newPassword: password, sessionStore: sessionStore)
                }
            }
            .sheet(item: $roomForm) { form in
                AdminRoomFormSheet(
                    form: form,
                    beacons: viewModel.beacons,
                    isSaving: viewModel.isSaving,
                    onSave: { draft in
                        await viewModel.saveRoom(form: draft, sessionStore: sessionStore)
                    },
                    onDelete: {
                        roomDeleteTarget = viewModel.rooms.first { $0.id == form.roomID }
                    }
                )
            }
            .sheet(item: $beaconForm) { form in
                AdminBeaconFormSheet(form: form, rooms: viewModel.rooms, isSaving: viewModel.isSaving) { draft in
                    await viewModel.saveBeacon(form: draft, sessionStore: sessionStore)
                }
            }
    }
}

private struct AdministrationAlerts: ViewModifier {
    @Binding var deleteTarget: AdminUser?
    @Binding var roomDeleteTarget: Room?
    @Binding var beaconDeleteTarget: AdminBeacon?
    @ObservedObject var viewModel: AdministrationViewModel
    @ObservedObject var sessionStore: SessionStore

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete Profile?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                presenting: deleteTarget
            ) { user in
                Button("Delete Profile", role: .destructive) {
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
}

private struct AdministrationToolbar: View {
    @Binding var searchText: String
    let applyFilters: () -> Void
    let addUser: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Label("User Management", systemImage: "person.3.fill")
                .aegisH2()

            Spacer()

            SearchField(text: $searchText, placeholder: "Search by Name...")
                .frame(width: 265)
                .onSubmit {
                    applyFilters()
                }

            Button(action: addUser) {
                Label("Add New Learner", systemImage: "plus")
                    .font(AegisTypography.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background {
                        AegisButtonBackground()
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RoomManagementToolbar: View {
    let addRoom: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Room Management", systemImage: "house.fill")
                .aegisH2()

            Spacer()

            Button(action: addRoom) {
                Label("Add New Room", systemImage: "plus")
                    .font(AegisTypography.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background {
                        AegisButtonBackground()
                    }
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
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct AdminPaginationFooter: View {
    let summary: String
    let message: String?
    let successWords: [String]
    let canGoPrevious: Bool
    let canGoNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AegisColors.mutedText)

            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSuccess(message) ? AegisColors.activeGreen : Color.red)
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

    private func isSuccess(_ message: String) -> Bool {
        successWords.contains { message.localizedCaseInsensitiveContains($0) }
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

        return 48 + bodyHeight + errorHeight
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
                .padding(.horizontal, 16)
                .frame(minWidth: 138)
                .frame(height: 34)
                .background(isSelected ? AegisColors.teal : Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.clear : AegisColors.panelBorder, lineWidth: 1)
                }
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

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Room Name", .infinity),
                ("Location", 180),
                ("Beacon Count", 170),
                ("Beacon Status", 170),
                ("Actions", 120)
            ])

            if case .loading = state {
                TableMessage("Loading rooms...")
            } else if rows.isEmpty {
                TableMessage("No rooms found.")
            } else {
                ForEach(rows) { room in
                    HStack(spacing: 0) {
                        Text(room.name).tableCell(maxWidth: .infinity, alignment: .leading)
                        Text("—").tableCell(width: 180, alignment: .leading)
                        Text("\(beaconCount(room)) Sensors").tableCell(width: 170)
                        Text(beaconStatus(room))
                            .foregroundStyle(beaconCount(room) > 0 ? AegisColors.activeGreen : AegisColors.mutedText)
                            .tableCell(width: 170)

                        HStack {
                            IconActionButton(symbol: "pencil", tint: Color.blue) {
                                edit(room)
                            }
                            .help("Edit room")
                        }
                        .frame(width: 120)
                    }
                    .frame(height: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AegisColors.rowDivider).frame(height: 1)
                    }
                }
            }

            if case let .failed(message) = state {
                ErrorBanner(message: message)
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
                        Rectangle().fill(AegisColors.rowDivider).frame(height: 1)
                    }
                }
            }

            if case let .failed(message) = state {
                ErrorBanner(message: message)
                    .padding(.top, 12)
            }
        }
    }
}

private struct AdminUsersTable: View {
    let rows: [AdminUser]
    let state: LoadState
    let edit: (AdminUser) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Learner", .infinity),
                ("Session", 130),
                ("E-mail", 250),
                ("ID", 130),
                ("Actions", 110)
            ])

            if case .loading = state {
                TableMessage("Loading users...")
            } else if rows.isEmpty {
                TableMessage("No users found.")
            } else {
                ForEach(rows) { user in
                    HStack(spacing: 0) {
                        Text(user.displayName)
                            .tableCell(maxWidth: .infinity, alignment: .leading)
                        Text(user.sessionDisplay).tableCell(width: 130)
                        Text(user.email).tableCell(width: 250)
                        Text(String(format: "%04d", user.id)).tableCell(width: 130)

                        HStack {
                            Button {
                                edit(user)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(AegisTypography.b2)
                                    .foregroundStyle(Color.blue)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .help("Edit learner profile")
                        }
                        .frame(width: 110)
                    }
                    .frame(height: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AegisColors.rowDivider).frame(height: 1)
                    }
                }
            }

            if case let .failed(message) = state {
                ErrorBanner(message: message)
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
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AdminUserFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AdminUserForm
    @State private var isShowingSessionOptions = false
    let isSaving: Bool
    let onSave: (AdminUserForm) async -> Bool
    let onDelete: () -> Void

    init(
        form: AdminUserForm,
        isSaving: Bool,
        onSave: @escaping (AdminUserForm) async -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self._draft = State(initialValue: form)
        self.isSaving = isSaving
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(draft.title)
                    .aegisH2()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(AegisTypography.h2)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text("Learner Details")
                    .font(AegisTypography.b2.weight(.semibold))

                HStack(spacing: 14) {
                    FormTextField(title: "Learner ID", text: $draft.username)
                        .disabled(draft.isEditing)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session")
                            .font(AegisTypography.caption)
                            .foregroundStyle(AegisColors.mutedText)
                        Button {
                            isShowingSessionOptions.toggle()
                        } label: {
                            HStack {
                                Text(draft.session.isEmpty ? "Select Session" : draft.session)
                                    .foregroundStyle(draft.session.isEmpty ? AegisColors.mutedText : .black)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundStyle(AegisColors.mutedText)
                            }
                            .font(AegisTypography.b2)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.55), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingSessionOptions, arrowEdge: .bottom) {
                            VStack(spacing: 0) {
                                sessionOption("AM")
                                Divider()
                                sessionOption("PM")
                            }
                            .padding(6)
                            .frame(width: 250)
                        }
                    }
                }

                HStack(spacing: 14) {
                    FormTextField(title: "First Name", text: $draft.firstName)
                    FormTextField(title: "Last Name", text: $draft.lastName)
                }

                Text("Contact Information")
                    .font(AegisTypography.b2.weight(.semibold))

                HStack(spacing: 14) {
                    FormTextField(title: "Email Address", text: $draft.email)
                    if !draft.isEditing {
                        SecureFormField(title: "Password", text: $draft.password)
                    }
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()

            HStack {
                if draft.isEditing {
                    Button {
                        dismiss()
                        onDelete()
                    } label: {
                        Label("Delete Profile", systemImage: "trash")
                            .font(AegisTypography.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Color.red.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    Task {
                        if await onSave(draft) {
                            dismiss()
                        }
                    }
                } label: {
                    Text(draft.submitTitle)
                        .frame(width: 180)
                }
                .buttonStyle(AegisPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSubmit || isSaving)
            }
            .padding(16)
        }
        .frame(width: 660, height: draft.isEditing ? 430 : 470)
    }

    private func sessionOption(_ session: String) -> some View {
        Button {
            draft.session = session
            isShowingSessionOptions = false
        } label: {
            HStack {
                Text(session)
                Spacer()
                if draft.session == session {
                    Image(systemName: "checkmark")
                }
            }
            .font(AegisTypography.b2)
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PasswordResetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    let user: AdminUser
    let isSaving: Bool
    let onSave: (String) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reset Password")
                .font(.system(size: 18, weight: .bold))
            Text(user.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AegisColors.mutedText)
            SecureFormField(title: "New Password", text: $password)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Reset Password") {
                    Task {
                        if await onSave(password) {
                            dismiss()
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
    @State private var location = "North Wing"
    @State private var beaconSlots: [Int?]
    let beacons: [AdminBeacon]
    let isSaving: Bool
    let onSave: (AdminRoomForm) async -> Bool
    let onDelete: () -> Void

    init(
        form: AdminRoomForm,
        beacons: [AdminBeacon],
        isSaving: Bool,
        onSave: @escaping (AdminRoomForm) async -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self._draft = State(initialValue: form)
        let assigned = beacons
            .filter { $0.roomID == form.roomID }
            .map { Optional($0.id) }
        self._beaconSlots = State(initialValue: assigned + Array(repeating: nil, count: max(0, 3 - assigned.count)))
        self.beacons = beacons
        self.isSaving = isSaving
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(draft.title)
                    .aegisH2()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(AegisTypography.h2)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text("Room Details")
                    .font(AegisTypography.b2.weight(.semibold))

                HStack(alignment: .bottom, spacing: 40) {
                    FormTextField(title: "Room Name", text: $draft.name)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Location")
                            .font(AegisTypography.caption)
                            .foregroundStyle(AegisColors.mutedText)
                        Picker("Location", selection: $location) {
                            Text("North Wing").tag("North Wing")
                            Text("South Wing").tag("South Wing")
                        }
                        .labelsHidden()
                    }
                    .frame(width: 240)
                }

                ForEach(beaconSlots.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Beacon ID \(index + 1)")
                            .font(AegisTypography.caption)
                            .foregroundStyle(AegisColors.mutedText)
                        Picker("Beacon ID \(index + 1)", selection: $beaconSlots[index]) {
                            Text("Select Beacon").tag(Optional<Int>.none)
                            ForEach(beacons) { beacon in
                                Text(beacon.beaconIdentifier).tag(Optional(beacon.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 335)
                    }
                }

                Button {
                    beaconSlots.append(nil)
                } label: {
                    Label("Add New Beacon ID", systemImage: "plus")
                        .font(AegisTypography.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.gray.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()

            HStack {
                if draft.isEditing {
                    Button {
                        dismiss()
                        onDelete()
                    } label: {
                        Label("Delete Room", systemImage: "trash")
                            .font(AegisTypography.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Color.red.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                Button {
                    Task {
                        if await onSave(draft) {
                            dismiss()
                        }
                    }
                } label: {
                    Text(draft.submitTitle)
                        .frame(width: 180)
                }
                .buttonStyle(AegisPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSubmit || isSaving)
            }
            .padding(16)
        }
        .frame(width: 690, height: 620)
    }
}

private struct AdminBeaconFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AdminBeaconForm
    let rooms: [Room]
    let isSaving: Bool
    let onSave: (AdminBeaconForm) async -> Bool

    init(form: AdminBeaconForm, rooms: [Room], isSaving: Bool, onSave: @escaping (AdminBeaconForm) async -> Bool) {
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
                        if await onSave(draft) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSubmit || isSaving)
            }
            .padding(16)
        }
        .frame(width: 620, height: 340)
    }
}
