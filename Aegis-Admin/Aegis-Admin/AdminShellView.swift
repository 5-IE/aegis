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
                    .font(.system(size: 34, weight: .semibold))
                Text("Aegis")
                    .font(.system(size: 36, weight: .bold))
            }
            .foregroundStyle(AegisColors.teal)
            .padding(.top, 40)
            .padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 20) {
                ForEach(AdminSection.allCases) { section in
                    SidebarItem(section: section, isSelected: section == selection) {
                        selection = section
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

private struct SidebarItem: View {
    let section: AdminSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 28)

                Text(section.rawValue)
                    .font(AegisTypography.b1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : AegisColors.mutedText)
            .frame(height: 52)
            .padding(.horizontal, 20)
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
