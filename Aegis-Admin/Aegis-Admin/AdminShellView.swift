import SwiftUI

struct AdminShellView: View {
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
                administrationMode: $administrationViewModel.selectedMode,
                user: user,
                signOut: { Task { await sessionStore.signOut() } }
            )
            .frame(width: 240)

            ZStack {
                AegisColors.appBackground
                activeScreen
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: administrationViewModel.selectedMode) { _, mode in
            administrationViewModel.selectMode(mode, sessionStore: sessionStore)
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
    @Binding var administrationMode: AdministrationMode
    let user: UserSession
    let signOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image("aegis mac")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                Text("Aegis")
                    .font(.system(size: 36, weight: .bold))
            }
            .foregroundStyle(AegisColors.teal)
            .padding(.top, 40)
            .padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 20) {
                ForEach(AdminSection.allCases) { section in
                    VStack(spacing: 10) {
                        SidebarItem(section: section, isSelected: section == selection) {
                            selection = section
                        }

                        if section == .administration && selection == .administration {
                            AdministrationSubmenu(selection: $administrationMode)
                        }
                    }
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 20)

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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName == "admin" ? "Admin" : user.displayName)
                            .font(AegisTypography.b1)
                            .foregroundStyle(AegisColors.tealDark)
                            .lineLimit(1)
                        Text("Sign out")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AegisColors.mutedText)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.clear)
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AegisColors.panelBorder)
                .frame(width: 1)
        }
    }
}

private struct AdministrationSubmenu: View {
    @Binding var selection: AdministrationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(AdministrationMode.allCases.enumerated()), id: \.element.id) { index, mode in
                HStack(spacing: 10) {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.45))
                            .frame(width: 1, height: 36)
                            .opacity(index == AdministrationMode.allCases.count - 1 ? 0 : 1)
                            .offset(y: 18)
                        Circle()
                            .fill(selection == mode ? AegisColors.teal : Color.gray.opacity(0.70))
                            .frame(width: 7, height: 7)
                    }
                    .frame(width: 14, height: 36)

                    Button {
                        selection = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(AegisTypography.caption)
                            .foregroundStyle(selection == mode ? .white : AegisColors.mutedText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background {
                                if selection == mode {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AegisColors.secondaryTeal)
                                        .overlay {
                                            HStack {
                                                Ellipse()
                                                    .fill(Color.white.opacity(0.28))
                                                    .frame(width: 34, height: 46)
                                                    .blur(radius: 12)
                                                    .offset(x: -18)
                                                Spacer()
                                                Ellipse()
                                                    .fill(Color.white.opacity(0.24))
                                                    .frame(width: 34, height: 46)
                                                    .blur(radius: 12)
                                                    .offset(x: 18)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
    }
}

private struct SidebarItem: View {
    let section: AdminSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 24)

                Text(section.rawValue)
                    .font(AegisTypography.b1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : AegisColors.mutedText)
            .frame(height: 52)
            .padding(.horizontal, 12)
            .background {
                if isSelected {
                    AegisButtonBackground()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
