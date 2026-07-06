import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AdminViewModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $viewModel.selectedSection)
                .frame(width: 244)

            Group {
                switch viewModel.selectedSection {
                case .dashboard:
                    DashboardView(snapshot: viewModel.dashboard)
                case .liveRadar:
                    LiveRadarView(
                        rooms: viewModel.rooms,
                        selectedRoomID: $viewModel.selectedRoomID,
                        selectedRoom: viewModel.selectedRoom
                    )
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1120, minHeight: 760)
        .background(activeBackground)
    }

    private var activeBackground: some View {
        Group {
            if viewModel.selectedSection == .liveRadar {
                AegisColors.liveBackground
            } else {
                AegisColors.dashboardBackground
            }
        }
    }
}

private enum AegisColors {
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let mutedText = Color(red: 0.40, green: 0.42, blue: 0.43)
    static let teal = Color(red: 0.30, green: 0.42, blue: 0.45)
    static let tealDark = Color(red: 0.24, green: 0.35, blue: 0.38)
    static let divider = Color(red: 0.74, green: 0.75, blue: 0.75)
    static let dashboardBackground = Color(red: 0.985, green: 0.985, blue: 0.985)
    static let sidebarBackground = Color(red: 0.99, green: 0.99, blue: 0.99)
    static let cardShadow = Color.black.opacity(0.20)
    static let activeBlue = Color(red: 0.31, green: 0.39, blue: 0.74)
    static let activeGreen = Color(red: 0.30, green: 0.72, blue: 0.27)
    static let inactiveYellow = Color(red: 0.78, green: 0.69, blue: 0.20)
    static let beaconBlue = Color(red: 0.29, green: 0.31, blue: 0.58)

    static var liveBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.71, green: 0.84, blue: 0.88),
                    Color(red: 0.88, green: 0.92, blue: 0.86),
                    Color(red: 0.72, green: 0.86, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(0.58),
                    Color.white.opacity(0.05)
                ],
                center: .center,
                startRadius: 80,
                endRadius: 720
            )
            RadialGradient(
                colors: [
                    Color(red: 0.79, green: 0.86, blue: 0.65).opacity(0.32),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 70,
                endRadius: 520
            )
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: AdminSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 34, weight: .semibold))
                Text("Aegis")
                    .font(.system(size: 31, weight: .bold))
            }
            .foregroundStyle(AegisColors.teal)
            .padding(.top, 42)
            .padding(.horizontal, 34)

            VStack(alignment: .leading, spacing: 21) {
                ForEach(AdminSection.allCases) { section in
                    SidebarItem(
                        section: section,
                        isSelected: section == selection
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 14)

            Spacer()
        }
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(selection == .liveRadar ? 0.15 : 0.03))
                .frame(width: 1)
        }
    }

    private var sidebarBackground: some View {
        Group {
            if selection == .liveRadar {
                AegisColors.liveBackground
                    .opacity(0.82)
            } else {
                AegisColors.sidebarBackground
            }
        }
    }
}

private struct SidebarItem: View {
    let section: AdminSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 24)

                Text(section.rawValue)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(isSelected ? Color.white : AegisColors.mutedText)
            .frame(height: 43)
            .padding(.horizontal, 18)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AegisColors.teal)
                        .overlay(alignment: .trailing) {
                            RadialGradient(
                                colors: [Color.white.opacity(0.32), .clear],
                                center: .trailing,
                                startRadius: 0,
                                endRadius: 42
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            TopBar(title: "Dashboard", textColor: AegisColors.ink)

            HStack(spacing: 38) {
                PresentSummaryCard(snapshot: snapshot)
                    .frame(maxWidth: .infinity)

                AbsentSummaryCard(snapshot: snapshot)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 180)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .shadow(color: AegisColors.cardShadow.opacity(0.55), radius: 6, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 57)
        .padding(.leading, 30)
        .padding(.trailing, 35)
        .padding(.bottom, 32)
        .background(AegisColors.dashboardBackground)
    }
}

private struct TopBar: View {
    let title: String
    let textColor: Color

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(textColor)

            Spacer()

            ProfileButton()
        }
        .frame(height: 39)
    }
}

private struct ProfileButton: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.58, green: 0.58, blue: 0.58))

            Image(systemName: "person.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white)
                .offset(y: 1)
        }
        .frame(width: 50, height: 50)
    }
}

private struct PresentSummaryCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(AegisColors.activeBlue)
                        .frame(width: 40, height: 40)

                    Text("Present Summary")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AegisColors.teal)
                }

                HStack(alignment: .top, spacing: 25) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("On time")
                            Image(systemName: "person.fill.checkmark")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AegisColors.mutedText)

                        Text("\(snapshot.onTime)")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(AegisColors.divider)
                        .frame(width: 1, height: 78)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Late Clock-in")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AegisColors.mutedText)

                        Text("\(snapshot.lateClockIn)")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct AbsentSummaryCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 13) {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(AegisColors.teal)
                        .frame(width: 30)

                    Text("Absent Summary")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AegisColors.teal)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Absent")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AegisColors.mutedText)

                        Text(snapshot.absent == 0 ? " " : "\(snapshot.absent)")
                            .font(.system(size: 28, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(AegisColors.divider)
                        .frame(width: 1, height: 82)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("No Clock-in")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AegisColors.mutedText)

                        Text(snapshot.noClockIn == 0 ? " " : "\(snapshot.noClockIn)")
                            .font(.system(size: 28, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct SummaryCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 27)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: AegisColors.cardShadow, radius: 6, x: 0, y: 3)
    }
}

private struct LiveRadarView: View {
    let rooms: [RoomSnapshot]
    @Binding var selectedRoomID: String
    let selectedRoom: RoomSnapshot

    var body: some View {
        ZStack {
            AegisColors.liveBackground

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TopBar(title: "Live Radar", textColor: .black)

                    RoomTabs(rooms: rooms, selectedRoomID: $selectedRoomID)

                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            RadarMapCard(room: selectedRoom)
                                .frame(height: 410)

                            OccupantsTable(room: selectedRoom)
                                .frame(height: 255)
                        }
                        .frame(maxWidth: .infinity)

                        MetricsColumn(room: selectedRoom)
                            .frame(width: 276)
                    }
                }
                .padding(.top, 58)
                .padding(.leading, 28)
                .padding(.trailing, 35)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct RoomTabs: View {
    let rooms: [RoomSnapshot]
    @Binding var selectedRoomID: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(rooms) { room in
                Button {
                    selectedRoomID = room.id
                } label: {
                    Text(room.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(room.id == selectedRoomID ? Color.white : Color.gray)
                        .frame(width: 114, height: 37)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(room.id == selectedRoomID ? AegisColors.teal : Color.white.opacity(0.92))
                                .shadow(
                                    color: room.id == selectedRoomID ? Color.black.opacity(0.16) : .clear,
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }
}

private struct RadarMapCard: View {
    let room: RoomSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 20, weight: .semibold))

                    Text("Live Trilateration Map")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.black)

                Spacer()

                HStack(spacing: 22) {
                    LegendItem(color: AegisColors.activeGreen, label: "Active")
                    LegendItem(color: AegisColors.inactiveYellow, label: "Inactive")
                }
            }
            .padding(.horizontal, 2)

            RadarPlot(room: room)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .glassPanel()
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
                .foregroundStyle(.black)
        }
    }
}

private struct RadarPlot: View {
    let room: RoomSnapshot

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = CGRect(
                x: size.width * 0.055,
                y: size.height * 0.085,
                width: size.width * 0.90,
                height: size.height * 0.82
            )

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.085))

                Path { path in
                    path.addRoundedRect(in: plotRect, cornerSize: CGSize(width: 8, height: 8))
                }
                .stroke(Color(red: 0.30, green: 0.36, blue: 0.60).opacity(0.82), lineWidth: 1)

                ForEach(room.radarPoints) { point in
                    Circle()
                        .fill(point.status == .active ? AegisColors.activeGreen : AegisColors.inactiveYellow)
                        .frame(width: 18, height: 18)
                        .position(x: size.width * point.x, y: size.height * point.y)
                }

                ForEach(room.beacons) { beacon in
                    BeaconMarker(beacon: beacon)
                        .position(x: size.width * beacon.x, y: size.height * beacon.y)
                }
            }
        }
    }
}

private struct BeaconMarker: View {
    let beacon: Beacon

    var body: some View {
        VStack(spacing: 2) {
            if beacon.y < 0.5 {
                label
            }

            Circle()
                .fill(AegisColors.beaconBlue)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.2))
                .frame(width: 18, height: 18)

            if beacon.y >= 0.5 {
                label
            }
        }
    }

    private var label: some View {
        Text(beacon.label)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color(red: 0.26, green: 0.30, blue: 0.56))
    }
}

private struct MetricsColumn: View {
    let room: RoomSnapshot

    var body: some View {
        VStack(spacing: 21) {
            MetricCard(
                icon: "thermometer.medium",
                iconColor: Color(red: 0.93, green: 0.42, blue: 0.49),
                iconBackground: Color(red: 1.0, green: 0.68, blue: 0.72),
                title: "Room Temperature",
                value: room.temperature
            )

            MetricCard(
                icon: "humidity.fill",
                iconColor: Color(red: 0.17, green: 0.58, blue: 0.70),
                iconBackground: Color(red: 0.66, green: 0.88, blue: 0.93),
                title: "Humidity",
                value: room.humidity
            )

            MetricCard(
                icon: "person.3.fill",
                iconColor: Color(red: 0.24, green: 0.60, blue: 0.22),
                iconBackground: Color(red: 0.69, green: 0.91, blue: 0.66),
                title: "People in Room",
                value: "\(room.peopleCount)"
            )
        }
    }
}

private struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(iconBackground.opacity(0.86))

                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(height: 100)
        .glassPanel()
    }
}

private struct OccupantsTable: View {
    let room: RoomSnapshot

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .bold))

                Text("Current Occupants")
                    .font(.system(size: 16, weight: .bold))

                Spacer()
            }
            .foregroundStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 22)

            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(height: 1)

            VStack(spacing: 10) {
                OccupantRow(
                    learner: "Learner",
                    session: "Learner's Session",
                    duration: "Duration",
                    status: "Status",
                    isHeader: true
                )

                ForEach(room.occupants) { occupant in
                    OccupantRow(
                        learner: occupant.learner,
                        session: occupant.session,
                        duration: occupant.duration,
                        status: occupant.status,
                        isHeader: false
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .glassPanel()
    }
}

private struct OccupantRow: View {
    let learner: String
    let session: String
    let duration: String
    let status: String
    let isHeader: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(learner)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(session)
                .frame(width: 190, alignment: .leading)

            Text(duration)
                .frame(width: 112, alignment: .leading)

            Text(status)
                .frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 14, weight: isHeader ? .bold : .medium))
        .foregroundStyle(.black)
        .lineLimit(1)
    }
}

private struct SettingsView: View {
    @State private var refreshInterval = 5.0
    @State private var liveUpdatesEnabled = true
    @State private var selectedEnvironment = "Development"

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            TopBar(title: "Settings", textColor: AegisColors.ink)

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsPanelTitle("API Configuration")

                    VStack(spacing: 14) {
                        SettingsField(label: "Environment") {
                            Picker("", selection: $selectedEnvironment) {
                                Text("Development").tag("Development")
                                Text("Staging").tag("Staging")
                                Text("Production").tag("Production")
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }

                        SettingsTextRow(label: "Base URL", value: "Waiting for backend")
                        SettingsTextRow(label: "Auth Method", value: "Bearer token")
                    }
                }
                .settingsCard(width: 430)

                VStack(alignment: .leading, spacing: 18) {
                    SettingsPanelTitle("Live Data")

                    Toggle("Enable live updates", isOn: $liveUpdatesEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 15, weight: .semibold))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Refresh Interval")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(Int(refreshInterval))s")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AegisColors.teal)
                        }

                        Slider(value: $refreshInterval, in: 2...30, step: 1)
                    }
                }
                .settingsCard(width: 330)
            }

            Spacer()
        }
        .padding(.top, 57)
        .padding(.leading, 30)
        .padding(.trailing, 35)
        .padding(.bottom, 32)
        .background(AegisColors.dashboardBackground)
    }
}

private struct SettingsPanelTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.black)
    }
}

private struct SettingsField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AegisColors.mutedText)

            Spacer()

            content
        }
    }
}

private struct SettingsTextRow: View {
    let label: String
    let value: String

    var body: some View {
        SettingsField(label: label) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.black.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private extension View {
    func settingsCard(width: CGFloat) -> some View {
        self
            .padding(24)
            .frame(width: width, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: AegisColors.cardShadow.opacity(0.30), radius: 6, x: 0, y: 2)
    }

    func glassPanel() -> some View {
        self
            .background(Color.white.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.1)
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 1342, height: 856)
    }
}
