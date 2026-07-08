import SwiftUI

struct ContentView: View {
    @StateObject private var sessionStore = SessionStore()

    var body: some View {
        Group {
            switch sessionStore.state {
            case .restoring:
                RestoringSessionView()
            case .signedOut:
                LoginView(sessionStore: sessionStore)
            case let .signedIn(user):
                AdminShellView(sessionStore: sessionStore, user: user)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .task {
            await sessionStore.restoreSession()
        }
    }
}

enum AegisColors {
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let mutedText = Color(red: 0.42, green: 0.45, blue: 0.46)
    static let teal = Color(red: 0.30, green: 0.42, blue: 0.45)
    static let tealDark = Color(red: 0.24, green: 0.36, blue: 0.39)
    static let tableHeader = Color(red: 0.70, green: 0.82, blue: 0.85)
    static let dashboardBackground = Color(red: 0.985, green: 0.985, blue: 0.985)
    static let panelBorder = Color.black.opacity(0.08)
    static let cardShadow = Color.black.opacity(0.16)
    static let activeGreen = Color(red: 0.24, green: 0.70, blue: 0.25)
    static let inactiveYellow = Color(red: 0.77, green: 0.68, blue: 0.20)
    static let beaconBlue = Color(red: 0.29, green: 0.31, blue: 0.58)

    static var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.70, green: 0.84, blue: 0.88),
                    Color(red: 0.88, green: 0.92, blue: 0.86),
                    Color(red: 0.72, green: 0.86, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.52), Color.white.opacity(0.04)],
                center: .center,
                startRadius: 70,
                endRadius: 700
            )
            RadialGradient(
                colors: [Color(red: 0.78, green: 0.86, blue: 0.65).opacity(0.32), .clear],
                center: .bottomTrailing,
                startRadius: 70,
                endRadius: 500
            )
        }
    }
}

private struct RestoringSessionView: View {
    var body: some View {
        ZStack {
            AegisColors.appBackground
            ProgressView()
                .controlSize(.large)
        }
    }
}

private struct LoginView: View {
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        GeometryReader { proxy in
            let layout = LoginLayout(size: proxy.size)

            if layout.usesCompactLayout {
                compactLayout(layout)
            } else {
                wideLayout(layout)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea()
    }

    private func wideLayout(_ layout: LoginLayout) -> some View {
        HStack(spacing: 0) {
            loginForm
                .frame(width: layout.formWidth, alignment: .leading)
                .frame(width: layout.leftPaneWidth)
                .frame(maxHeight: .infinity, alignment: .center)

            wideLoginHero
                .frame(width: layout.heroWidth)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactLayout(_ layout: LoginLayout) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                loginForm
                    .frame(width: layout.compactFormWidth, alignment: .leading)

                loginHero
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.compactHeroHeight)
            }
            .padding(.horizontal, layout.compactHorizontalPadding)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome to Aegis")
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.bottom, 12)

            Text("Login to manage your account")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AegisColors.mutedText)
                .lineLimit(1)
                .padding(.bottom, 28)

            LoginInputField(
                icon: "person",
                placeholder: "Enter your email or phone",
                text: $viewModel.username
            )
            .padding(.bottom, 16)

            LoginSecureField(
                icon: "lock",
                placeholder: "Enter your password",
                text: $viewModel.password
            )
            .padding(.bottom, 10)

            HStack {
                Spacer()
                Button("Forgot Password?") {
                    viewModel.disabledFeatureMessage = "Password reset is not available yet."
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AegisColors.teal)
            }
            .padding(.bottom, 27)

            Button {
                Task { await viewModel.signIn(sessionStore: sessionStore) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AegisColors.teal)
                        .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 2)

                    if viewModel.isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("SIGN IN")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.58)
            .padding(.bottom, 28)

            HStack(spacing: 4) {
                Spacer()
                Text("Don't have account?")
                    .foregroundStyle(AegisColors.mutedText)
                Button("Sign Up") {
                    viewModel.disabledFeatureMessage = "Account registration is not available yet."
                }
                .buttonStyle(.plain)
                .foregroundStyle(AegisColors.teal)
                .fontWeight(.bold)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold))

            if let error = sessionStore.authError ?? viewModel.disabledFeatureMessage {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.75, green: 0.12, blue: 0.12))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loginHero: some View {
        Image("LoginHero")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipped()
    }

    private var wideLoginHero: some View {
        Image("LoginHero")
            .resizable()
            .scaledToFill()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 22,
                    style: .continuous
                )
            )
            .clipped()
    }
}

private struct LoginLayout {
    let size: CGSize

    var usesCompactLayout: Bool {
        size.width < 940 || size.height < 600
    }

    var compactHorizontalPadding: CGFloat {
        size.width < 520 ? 24 : 44
    }

    var leftPaneWidth: CGFloat {
        size.width * 0.5
    }

    var heroWidth: CGFloat {
        size.width - leftPaneWidth
    }

    var formWidth: CGFloat {
        min(max(leftPaneWidth * 0.68, 340), 520)
    }

    var compactFormWidth: CGFloat {
        min(460, max(280, size.width - (compactHorizontalPadding * 2)))
    }

    var compactHeroHeight: CGFloat {
        min(420, max(260, size.height * 0.42))
    }
}

private struct LoginInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.85))
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct LoginSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.85))
                .frame(width: 18)

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct AdminShellView: View {
    @ObservedObject var sessionStore: SessionStore
    let user: UserSession
    @State private var selectedSection: AdminSection = .dashboard
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @StateObject private var liveRadarViewModel = LiveRadarViewModel()
    @StateObject private var administrationViewModel = AdministrationViewModel()
    @StateObject private var reportsViewModel = ReportsViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                selection: $selectedSection,
                user: user,
                signOut: { Task { await sessionStore.signOut() } }
            )
            .frame(width: 214)

            ZStack {
                AegisColors.appBackground
                activeScreen
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var activeScreen: some View {
        switch selectedSection {
        case .dashboard:
            DashboardView(viewModel: dashboardViewModel, sessionStore: sessionStore)
        case .liveRadar:
            LiveRadarView(viewModel: liveRadarViewModel, sessionStore: sessionStore)
        case .administration:
            AdministrationView(
                viewModel: administrationViewModel,
                sessionStore: sessionStore,
                currentAdminID: user.id
            )
        case .reports:
            ReportsView(viewModel: reportsViewModel, sessionStore: sessionStore)
        case .settings:
            SettingsView(viewModel: settingsViewModel, sessionStore: sessionStore)
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: AdminSection
    let user: UserSession
    let signOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 28, weight: .semibold))
                Text("Aegis")
                    .font(.system(size: 25, weight: .bold))
            }
            .foregroundStyle(AegisColors.teal)
            .padding(.top, 42)
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(AdminSection.allCases) { section in
                    SidebarItem(section: section, isSelected: section == selection) {
                        selection = section
                    }
                }
            }
            .padding(.top, 34)
            .padding(.horizontal, 18)

            Spacer()

            Button(action: signOut) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.70))
                        Image(systemName: "person.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)

                    Text(user.displayName == "admin" ? "Admin" : user.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AegisColors.tealDark)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1)
        }
    }
}

private struct SidebarItem: View {
    let section: AdminSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : AegisColors.mutedText)
            .frame(height: 34)
            .padding(.horizontal, 13)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AegisColors.teal)
                        .overlay(alignment: .trailing) {
                            RadialGradient(
                                colors: [Color.white.opacity(0.38), .clear],
                                center: .trailing,
                                startRadius: 0,
                                endRadius: 38
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            dashboardHeader
            summaryCards
            attendancePanel
        }
        .screenPadding()
        .task {
            if viewModel.state == .idle {
                await viewModel.load(sessionStore: sessionStore)
            }
        }
    }

    private var dashboardHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("Dashboard")
                    .screenTitle()
                Spacer()
                DateChip(text: viewModel.formattedDate)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Dashboard")
                    .screenTitle()
                DateChip(text: viewModel.formattedDate)
            }
        }
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 36) {
                PresentSummaryCard(summary: viewModel.summary)
                    .frame(minWidth: 300)
                AbsentSummaryCard(summary: viewModel.summary)
                    .frame(minWidth: 300)
            }
            .frame(height: 132)

            VStack(spacing: 18) {
                PresentSummaryCard(summary: viewModel.summary)
                    .frame(height: 132)
                AbsentSummaryCard(summary: viewModel.summary)
                    .frame(height: 132)
            }
        }
    }

    private var attendancePanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 15) {
                attendancePanelHeader
                AttendanceTable(rows: viewModel.overviewRows, state: viewModel.state)
                    .frame(minHeight: 180, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var attendancePanelHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                attendanceTitle
                Spacer()
                attendanceControls
            }

            VStack(alignment: .leading, spacing: 12) {
                attendanceTitle
                attendanceControls
            }
        }
    }

    private var attendanceTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Attendance Overview")
                .font(.system(size: 16, weight: .bold))
            Text(viewModel.shortDate)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AegisColors.mutedText)
        }
    }

    private var attendanceControls: some View {
        HStack(spacing: 12) {
            SearchField(text: $viewModel.searchText, placeholder: "Search by Name...")
                .frame(width: 210)
                .onSubmit {
                    Task { await viewModel.reloadOverview(sessionStore: sessionStore) }
                }

            Menu {
                Picker("Session", selection: $viewModel.sessionFilter) {
                    ForEach(SessionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                Button("Apply") {
                    Task { await viewModel.reloadOverview(sessionStore: sessionStore) }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AegisColors.teal)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white))
            }
            .menuStyle(.borderlessButton)
        }
    }
}

private struct PresentSummaryCard: View {
    let summary: DashboardSummary

    var body: some View {
        SummaryCard {
            HStack(alignment: .top, spacing: 15) {
                MetricIcon(symbol: "person.fill.checkmark", color: Color(red: 0.34, green: 0.68, blue: 0.73), background: Color(red: 0.75, green: 0.90, blue: 0.93))
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 21) {
                    Text("Present Summary")
                        .font(.system(size: 16, weight: .bold))
                    HStack(alignment: .top, spacing: 30) {
                        SummaryMetric(label: "On time", value: "\(summary.onTime)")
                        Divider()
                            .frame(height: 67)
                        SummaryMetric(label: "Late Clock-in", value: "\(summary.lateClockIn)")
                    }
                }
            }
        }
    }
}

private struct AbsentSummaryCard: View {
    let summary: DashboardSummary

    var body: some View {
        SummaryCard {
            HStack(alignment: .top, spacing: 15) {
                MetricIcon(symbol: "person.fill.xmark", color: AegisColors.teal, background: Color(red: 0.78, green: 0.91, blue: 0.94))
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 21) {
                    Text("Absent Summary")
                        .font(.system(size: 16, weight: .bold))
                    HStack(alignment: .top, spacing: 30) {
                        SummaryMetric(label: "Absent", value: "\(summary.absent)")
                        Divider()
                            .frame(height: 67)
                        SummaryMetric(label: "No Clock-in", value: "\(summary.noClockIn)")
                    }
                }
            }
        }
    }
}

private struct SummaryCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(Color.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: AegisColors.cardShadow, radius: 5, x: 0, y: 2)
    }
}

private struct SummaryMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AegisColors.mutedText)
            Text(value)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttendanceTable: View {
    let rows: [AttendanceOverviewRow]
    let state: LoadState

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Learner", .infinity),
                ("Session", 110),
                ("Clock-in", 130),
                ("Clock-out", 130),
                ("Status", 110)
            ])

            if case .loading = state {
                TableMessage("Loading attendance...")
            } else if rows.isEmpty {
                TableMessage("No attendance data yet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.name).tableCell(maxWidth: .infinity, alignment: .leading)
                                Text(row.session).tableCell(width: 110)
                                Text(formatDateTime(row.clockedInAt)).tableCell(width: 130)
                                Text(formatDateTime(row.clockedOutAt)).tableCell(width: 130)
                                Text(row.status.titleCasedStatus)
                                    .foregroundStyle(statusColor(row.status))
                                    .tableCell(width: 110)
                            }
                            .frame(height: 46)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                            }
                        }
                    }
                }
                .frame(minHeight: 130, maxHeight: .infinity)
            }

            if case let .failed(message) = state {
                ErrorBanner(message: message)
                    .padding(.top, 12)
            }
        }
    }
}

private struct LiveRadarView: View {
    @ObservedObject var viewModel: LiveRadarViewModel
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Live Radar")
                    .screenTitle()

                roomTabs

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        radarMainColumn
                            .frame(minWidth: 520)
                        metricsColumn
                            .frame(width: 240)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        radarMainColumn
                        metricsResponsiveStack
                    }
                }
            }
            .screenPadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if viewModel.state == .idle {
                await viewModel.load(sessionStore: sessionStore)
            }
            viewModel.startPolling(sessionStore: sessionStore)
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    private var roomTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 11) {
                if viewModel.rooms.isEmpty {
                    RoomTab(title: "Room 1", isSelected: true) {}
                    RoomTab(title: "Room 2", isSelected: false) {}
                    RoomTab(title: "Room 3", isSelected: false) {}
                    RoomTab(title: "Room 4", isSelected: false) {}
                    RoomTab(title: "Room 5", isSelected: false) {}
                } else {
                    ForEach(viewModel.rooms) { room in
                        RoomTab(title: room.name, isSelected: room.id == viewModel.selectedRoomID) {
                            viewModel.select(roomID: room.id, sessionStore: sessionStore)
                        }
                    }
                }
            }
            .padding(.bottom, 1)
        }
    }

    private var radarMainColumn: some View {
        VStack(spacing: 20) {
            RadarMapCard(points: viewModel.radarPoints, state: viewModel.state)
                .frame(minHeight: 280, idealHeight: 340, maxHeight: 380)

            WhitePanel {
                VStack(alignment: .leading, spacing: 14) {
                    occupantsHeader
                    OccupantsTable(rows: viewModel.filteredOccupants, state: viewModel.state)
                        .frame(minHeight: 150, maxHeight: 260)
                }
            }
        }
    }

    private var occupantsHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                occupantsTitle
                Spacer()
                occupantsControls
            }

            VStack(alignment: .leading, spacing: 12) {
                occupantsTitle
                occupantsControls
            }
        }
    }

    private var occupantsTitle: some View {
        Label("Current Occupants", systemImage: "person.2.fill")
            .font(.system(size: 16, weight: .bold))
    }

    private var occupantsControls: some View {
        HStack(spacing: 12) {
            SearchField(text: $viewModel.occupantsSearchText, placeholder: "Search by Name...")
                .frame(width: 210)
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AegisColors.teal)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white))
        }
    }

    private var metricsColumn: some View {
        VStack(spacing: 22) {
            temperatureMetric
            humidityMetric
            peopleMetric
        }
    }

    private var metricsResponsiveStack: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                temperatureMetric
                humidityMetric
                peopleMetric
            }
            VStack(spacing: 14) {
                temperatureMetric
                humidityMetric
                peopleMetric
            }
        }
    }

    private var temperatureMetric: some View {
        MetricCard(
            icon: "thermometer.medium",
            iconColor: Color(red: 0.93, green: 0.42, blue: 0.49),
            iconBackground: Color(red: 1.0, green: 0.68, blue: 0.72),
            title: "Room Temperature",
            value: String(format: "%.1f\u{00B0}C", viewModel.metrics.temperature).replacingOccurrences(of: ".", with: ",")
        )
    }

    private var humidityMetric: some View {
        MetricCard(
            icon: "humidity.fill",
            iconColor: Color(red: 0.17, green: 0.58, blue: 0.70),
            iconBackground: Color(red: 0.66, green: 0.88, blue: 0.93),
            title: "Humidity",
            value: "\(Int(viewModel.metrics.humidity.rounded()))%"
        )
    }

    private var peopleMetric: some View {
        MetricCard(
            icon: "person.3.fill",
            iconColor: Color(red: 0.24, green: 0.60, blue: 0.22),
            iconBackground: Color(red: 0.69, green: 0.91, blue: 0.66),
            title: "People in Room",
            value: "\(viewModel.metrics.peopleInRoom)"
        )
    }
}

private struct RoomTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.gray)
                .frame(width: 108, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? AegisColors.teal : Color.white.opacity(0.92))
                }
        }
        .buttonStyle(.plain)
    }
}

private struct RadarMapCard: View {
    let points: [RadarPoint]
    let state: LoadState

    var body: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Live Trilateration Map", systemImage: "map")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    LegendItem(color: AegisColors.activeGreen, label: "Active")
                    LegendItem(color: AegisColors.inactiveYellow, label: "Inactive")
                }
                RadarPlot(points: points)
                    .overlay {
                        if case .loading = state {
                            ProgressView()
                        } else if points.isEmpty {
                            Text("No live map points.")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AegisColors.mutedText)
                        }
                    }
            }
        }
    }
}

private struct RadarPlot: View {
    let points: [RadarPoint]

    private let beacons = [
        BeaconMarkerData(label: "B01", x: 0.055, y: 0.085),
        BeaconMarkerData(label: "B02", x: 0.955, y: 0.085),
        BeaconMarkerData(label: "B03", x: 0.50, y: 0.90)
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = CGRect(
                x: size.width * 0.045,
                y: size.height * 0.075,
                width: size.width * 0.91,
                height: size.height * 0.82
            )

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.09))

                Path { path in
                    path.addRoundedRect(in: plotRect, cornerSize: CGSize(width: 7, height: 7))
                }
                .stroke(Color(red: 0.30, green: 0.36, blue: 0.60).opacity(0.75), lineWidth: 1)

                ForEach(points) { point in
                    Circle()
                        .fill(AegisColors.activeGreen)
                        .frame(width: 17, height: 17)
                        .position(x: size.width * point.x, y: size.height * point.y)
                        .help(point.userName)
                }

                ForEach(beacons) { beacon in
                    BeaconMarker(beacon: beacon)
                        .position(x: size.width * beacon.x, y: size.height * beacon.y)
                }
            }
        }
    }
}

private struct BeaconMarkerData: Identifiable {
    let id = UUID()
    let label: String
    let x: Double
    let y: Double
}

private struct BeaconMarker: View {
    let beacon: BeaconMarkerData

    var body: some View {
        VStack(spacing: 2) {
            if beacon.y < 0.5 { label }
            Circle()
                .fill(AegisColors.beaconBlue)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: 16, height: 16)
            if beacon.y >= 0.5 { label }
        }
    }

    private var label: some View {
        Text(beacon.label)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(AegisColors.beaconBlue)
    }
}

private struct OccupantsTable: View {
    let rows: [Occupant]
    let state: LoadState

    var body: some View {
        VStack(spacing: 0) {
            TableHeader(columns: [
                ("Learner", .infinity),
                ("Session", 100),
                ("Duration", 130),
                ("Status", 110),
                ("Last Update", 110)
            ])

            if case .loading = state {
                TableMessage("Loading occupants...")
            } else if rows.isEmpty {
                TableMessage("No current occupants.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.learner).tableCell(maxWidth: .infinity, alignment: .leading)
                                Text(row.session).tableCell(width: 100)
                                Text(row.formattedDuration).tableCell(width: 130)
                                Text(row.status.titleCasedStatus)
                                    .foregroundStyle(statusColor(row.status))
                                    .tableCell(width: 110)
                                Text("Now").tableCell(width: 110)
                            }
                            .frame(height: 46)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                            }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: .infinity)
            }

            if case let .failed(message) = state {
                ErrorBanner(message: message)
                    .padding(.top, 12)
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                Text("Settings")
                    .screenTitle()

                WhitePanel {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("Attendance Setting", systemImage: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))

                        SettingsSubpanel(title: "Session Thresholds", icon: "clock") {
                            VStack(spacing: 18) {
                                SessionThresholdRow(title: "AM Session", config: $viewModel.sessionConfigs.am)
                                SessionThresholdRow(title: "PM Session", config: $viewModel.sessionConfigs.pm)
                            }
                        }

                        SettingsSubpanel(title: "Late Check-in", icon: "clock.badge.exclamationmark") {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) {
                                    TimeField(text: $viewModel.sessionConfigs.am.lateAfter)
                                    Text("AM tolerance")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AegisColors.mutedText)
                                    TimeField(text: $viewModel.sessionConfigs.pm.lateAfter)
                                    Text("PM tolerance")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AegisColors.mutedText)
                                    Spacer()
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        TimeField(text: $viewModel.sessionConfigs.am.lateAfter)
                                        Text("AM tolerance")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AegisColors.mutedText)
                                    }
                                    HStack(spacing: 12) {
                                        TimeField(text: $viewModel.sessionConfigs.pm.lateAfter)
                                        Text("PM tolerance")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AegisColors.mutedText)
                                    }
                                }
                            }
                            Text("Check-ins after the late threshold are marked late by the backend.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AegisColors.mutedText)
                        }

                        Label("User Presence Update Interval", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.top, 4)

                        SettingsSubpanel(title: "Adjust Interval", icon: "arrow.clockwise") {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    presenceStepper
                                    Spacer()
                                    timezoneField
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    presenceStepper
                                    timezoneField
                                }
                            }
                            Text("Set how long a presence ping stays active before the user is considered stale.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AegisColors.mutedText)
                        }

                        HStack {
                            if let message = viewModel.saveMessage {
                                Text(message)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(message == "Settings saved" ? AegisColors.activeGreen : Color.red)
                            }
                            Spacer()
                            Button {
                                Task { await viewModel.save(sessionStore: sessionStore) }
                            } label: {
                                Text(viewModel.isSaving ? "Saving..." : "Save Settings")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .frame(height: 34)
                                    .background(AegisColors.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isSaving)
                        }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)

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
    }

    private var presenceStepper: some View {
        Stepper(value: $viewModel.systemConfig.presenceStalenessMinutes, in: 1...60) {
            Text("\(viewModel.systemConfig.presenceStalenessMinutes) minutes")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 220)
    }

    private var timezoneField: some View {
        TextField("Timezone", text: $viewModel.systemConfig.timezone)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
    }
}

private struct SettingsSubpanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AegisColors.teal)
            content
        }
        .padding(20)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

private struct SessionThresholdRow: View {
    let title: String
    @Binding var config: SessionConfig

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                rowTitle
                TimeField(text: $config.startTime)
                SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                Text("to")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AegisColors.mutedText)
                TimeField(text: $config.endTime)
                SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                rowTitle
                HStack(spacing: 12) {
                    TimeField(text: $config.startTime)
                    SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                    Text("to")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AegisColors.mutedText)
                    TimeField(text: $config.endTime)
                    SessionPill(text: title.hasPrefix("AM") ? "AM" : "PM")
                }
            }
        }
    }

    private var rowTitle: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .frame(width: 110, alignment: .leading)
    }
}

private struct TimeField: View {
    @Binding var text: String

    var body: some View {
        TextField("00:00:00", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(width: 88, height: 25)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
    }
}

private struct SessionPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AegisColors.teal)
            .frame(width: 49, height: 25)
            .background(Color.black.opacity(0.04))
            .clipShape(Capsule())
    }
}

struct WhitePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(Color.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: AegisColors.cardShadow, radius: 5, x: 0, y: 2)
    }
}

private struct DateChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar")
            Text(text)
            Image(systemName: "chevron.down")
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.black)
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.gray)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.white)
        .clipShape(Capsule())
    }
}

private struct MetricIcon: View {
    let symbol: String
    let color: Color
    let background: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)
    }
}

private struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(iconBackground.opacity(0.90))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 23)
        .frame(height: 104)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10, weight: .bold))
        }
    }
}

struct TableHeader: View {
    let columns: [(String, CGFloat)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column.0)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(
                        minWidth: column.1 == .infinity ? 0 : column.1,
                        maxWidth: column.1 == .infinity ? .infinity : column.1,
                        alignment: .leading
                    )
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(AegisColors.tableHeader)
    }
}

struct TableMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AegisColors.mutedText)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0.72, green: 0.12, blue: 0.12))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1.0, green: 0.92, blue: 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension View {
    func screenTitle() -> some View {
        self
            .font(.system(size: 27, weight: .bold))
            .foregroundStyle(.black)
    }

    func screenPadding() -> some View {
        self
            .padding(.top, 42)
            .padding(.leading, 28)
            .padding(.trailing, 30)
            .padding(.bottom, 30)
    }

    func tableCell(width: CGFloat? = nil, maxWidth: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .frame(
                minWidth: width ?? 0,
                maxWidth: maxWidth ?? width ?? .infinity,
                alignment: alignment
            )
            .padding(.horizontal, 13)
    }
}

func statusColor(_ status: String) -> Color {
    let lowered = status.lowercased()
    if lowered.contains("active") || lowered.contains("on time") || lowered.contains("checked in") || lowered.contains("early") {
        return AegisColors.activeGreen
    }
    if lowered.contains("late") || lowered.contains("running") {
        return AegisColors.inactiveYellow
    }
    return AegisColors.mutedText
}

private func formatDateTime(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "-" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fallback = ISO8601DateFormatter()
    let date = formatter.date(from: iso) ?? fallback.date(from: iso)
    guard let date else { return iso }
    let output = DateFormatter()
    output.dateFormat = "HH:mm"
    return output.string(from: date)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 1280, height: 820)
    }
}
