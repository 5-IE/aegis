import SwiftUI

struct LiveRadarView: View {
    @ObservedObject var viewModel: LiveRadarViewModel
    @ObservedObject var sessionStore: SessionStore
    @State private var isShowingFilters = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Live Radar")
                    .aegisH1()

                roomTabs

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        radarMainColumn
                            .frame(minWidth: 520)
                        metricsColumn
                            .frame(width: 260)
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
        .sheet(isPresented: $isShowingFilters) {
            OccupantsFilterSheet(viewModel: viewModel)
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
        VStack(spacing: 18) {
            RadarMapCard(points: viewModel.radarPoints, state: viewModel.state)
                .frame(minHeight: 280, idealHeight: 340, maxHeight: 380)

            WhitePanel {
                VStack(alignment: .leading, spacing: 4) {
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
            .aegisH2()
    }

    private var occupantsControls: some View {
        HStack(spacing: 12) {
            SearchField(text: $viewModel.occupantsSearchText, placeholder: "Search by Name...")
                .frame(width: 210)
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white))
                .onTapGesture {
                    isShowingFilters = true
                }
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
            title: "Temperature",
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
                .padding(.horizontal, 16)
                .frame(minWidth: 104)
                .frame(height: 34)
                .background {
                    if isSelected {
                        AegisButtonBackground()
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct OccupantsFilterSheet: View {
    @ObservedObject var viewModel: LiveRadarViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var session: SessionFilter
    @State private var statuses: Set<OccupantStatusFilter>

    init(viewModel: LiveRadarViewModel) {
        self.viewModel = viewModel
        _session = State(initialValue: viewModel.occupantsSessionFilter)
        _statuses = State(initialValue: viewModel.occupantsStatusFilters)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 38)
            .frame(height: 88)

            Divider()

            VStack(alignment: .leading, spacing: 30) {
                filterSection(title: "Session") {
                    HStack(spacing: 64) {
                        ForEach(SessionFilter.allCases) { item in
                            filterOption(
                                title: item.rawValue,
                                isSelected: session == item
                            ) {
                                session = item
                            }
                            .frame(width: 112, alignment: .leading)
                        }
                    }
                }

                filterSection(title: "Status") {
                    HStack(spacing: 64) {
                        ForEach(OccupantStatusFilter.allCases) { item in
                            filterOption(
                                title: item.rawValue,
                                isSelected: statuses.contains(item)
                            ) {
                                if statuses.contains(item) {
                                    statuses.remove(item)
                                } else {
                                    statuses.insert(item)
                                }
                            }
                            .frame(width: 112, alignment: .leading)
                        }
                    }
                }

                Spacer()

                HStack {
                    Button("Remove Filter") {
                        session = .all
                        statuses = []
                        viewModel.occupantsSessionFilter = .all
                        viewModel.occupantsStatusFilters = []
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(AegisColors.mutedText)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.75), lineWidth: 1)
                    }

                    Spacer()

                    Button {
                        viewModel.occupantsSessionFilter = session
                        viewModel.occupantsStatusFilters = statuses
                        dismiss()
                    } label: {
                        Text("Apply Filters")
                            .font(AegisTypography.b2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 205, height: 38)
                            .background {
                                AegisButtonBackground()
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 38)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .frame(width: 760, height: 400)
        .background(Color.white)
    }

    private func filterSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
            content()
        }
    }

    private func filterOption(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.blue : Color.gray.opacity(0.28))
                Text(title)
                    .font(.system(size: 18))
                    .foregroundStyle(.black)
                    .lineLimit(1)
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
                        .aegisH2()
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.055))

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
                ("Session", .infinity),
                ("Duration", .infinity),
                ("Status", .infinity),
                ("Last Update", .infinity)
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
                                Text(row.session).tableCell(maxWidth: .infinity)
                                Text(row.formattedDuration).tableCell(maxWidth: .infinity)
                                Text(row.status.titleCasedStatus)
                                    .foregroundStyle(statusColor(row.status))
                                    .tableCell(maxWidth: .infinity)
                                Text("Now").tableCell(maxWidth: .infinity)
                            }
                            .frame(height: 46)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(AegisColors.rowDivider).frame(height: 1)
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
