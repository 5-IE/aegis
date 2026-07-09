import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var sessionStore: SessionStore

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
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
        .onChange(of: selectedDate) { _, newDate in
            print("Selected date:", newDate)
        }
    }

    private var dashboardHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("Dashboard")
                    .screenTitle()
                Spacer()
                Button {
                    showDatePicker.toggle()
                } label: {
                    DateChip(
                        text: selectedDate.formatted(
                            .dateTime
                                .day()
                                .month(.wide)
                                .year()
                        )
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePicker) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Dashboard")
                    .screenTitle()
                Button {
                    showDatePicker.toggle()
                } label: {
                    DateChip(
                        text: selectedDate.formatted(
                            .dateTime
                                .day()
                                .month(.wide)
                                .year()
                        )
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePicker) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                }
            }
        }
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 40) {
                PresentSummaryCard(summary: viewModel.summary)
                    .frame(minWidth: 300)
                AbsentSummaryCard(summary: viewModel.summary)
                    .frame(minWidth: 300)
            }
            .frame(height: 178)

            VStack(spacing: 18) {
                PresentSummaryCard(summary: viewModel.summary)
                    .frame(height: 178)
                AbsentSummaryCard(summary: viewModel.summary)
                    .frame(height: 178)
            }
        }
    }

    private var attendancePanel: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 28) {
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
                .aegisH2()
            Text(viewModel.shortDate)
                .font(AegisTypography.b2)
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

            FilterButton(
                sessionFilter: $viewModel.sessionFilter,
                statusFilters: $viewModel.statusFilters,
                onApply: {
                    Task { await viewModel.reloadOverview(sessionStore: sessionStore) }
                },
                onRemove: {
                    viewModel.sessionFilter = .all
                    viewModel.statusFilters = []
                    Task { await viewModel.reloadOverview(sessionStore: sessionStore) }
                }
            )
        }
    }
}

private struct FilterButton: View {
    @Binding var sessionFilter: SessionFilter
    @Binding var statusFilters: Set<AttendanceStatusFilter>
    let onApply: () -> Void
    let onRemove: () -> Void

    @State private var showFilters = false

    var body: some View {
        Button {
            showFilters.toggle()
        } label: {
            Image(systemName: showFilters ? "xmark" : "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AegisColors.teal)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle().stroke(AegisColors.panelBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFilters) {
            FiltersPanel(
                sessionFilter: $sessionFilter,
                statusFilters: $statusFilters,
                onApply: {
                    onApply()
                    showFilters = false
                },
                onRemove: {
                    onRemove()
                    showFilters = false
                },
                onClose: { showFilters = false }
            )
        }
    }
}

private struct FiltersPanel: View {
    @Binding var sessionFilter: SessionFilter
    @Binding var statusFilters: Set<AttendanceStatusFilter>
    let onApply: () -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filters")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Session")
                        .font(.system(size: 16, weight: .bold))
                    HStack(spacing: 32) {
                        ForEach(SessionFilter.allCases) { filter in
                            FilterCheckbox(
                                label: filter.rawValue,
                                isChecked: sessionFilter == filter
                            ) {
                                sessionFilter = filter
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Status")
                        .font(.system(size: 16, weight: .bold))
                    HStack(spacing: 32) {
                        ForEach(AttendanceStatusFilter.allCases) { status in
                            FilterCheckbox(
                                label: status.rawValue,
                                isChecked: statusFilters.contains(status)
                            ) {
                                if statusFilters.contains(status) {
                                    statusFilters.remove(status)
                                } else {
                                    statusFilters.insert(status)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)

            HStack {
                Button("Remove Filter", action: onRemove)
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AegisColors.panelBorder, lineWidth: 1)
                    )

                Spacer()

                Button("Apply Filters", action: onApply)
                    .buttonStyle(AegisPrimaryButtonStyle())
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}

private struct FilterCheckbox: View {
    let label: String
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isChecked ? AegisColors.teal : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isChecked ? Color.clear : Color.gray.opacity(0.4), lineWidth: 1.5)
                        )
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)

                Text(label)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle())   // ← add this line
        }
        .buttonStyle(.plain)
    }
}

private struct PresentSummaryCard: View {
    let summary: DashboardSummary

    var body: some View {
        SummaryCard {
            HStack(alignment: .top, spacing: 15) {
                MetricIcon(symbol: "person.fill.checkmark", color: .black, background: Color(red: 0.75, green: 0.90, blue: 0.93))
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 24) {
                    Text("Present Summary")
                        .aegisH2()
                    HStack(alignment: .top, spacing: 44) {
                        SummaryMetric(label: "On time", value: "\(summary.onTime)")
                        Divider()
                            .frame(height: 86)
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
                MetricIcon(symbol: "person.fill.xmark", color: .black, background: Color(red: 0.78, green: 0.91, blue: 0.94))
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 24) {
                    Text("Absent Summary")
                        .aegisH2()
                    HStack(alignment: .top, spacing: 44) {
                        SummaryMetric(label: "Absent", value: "\(summary.absent)")
                        Divider()
                            .frame(height: 86)
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
        AegisCard(padding: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 36)
                .padding(.vertical, 32)
        }
    }
}

private struct SummaryMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(label)
                .font(AegisTypography.b1)
                .foregroundStyle(AegisColors.mutedText)
            Text(value)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttendanceTable: View {
    let rows: [AttendanceOverviewRow]
    let state: LoadState

    private let columns: [GridItem] = [
        GridItem(.fixed(280), alignment: .leading),
        GridItem(.fixed(90), alignment: .leading),
        GridItem(.fixed(110), alignment: .leading),
        GridItem(.fixed(110), alignment: .leading),
        GridItem(.fixed(110), alignment: .leading)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            LazyVGrid(columns: columns, spacing: 0) {
                Text("Learner")
                Text("Session")
                Text("Clock-in")
                Text("Clock-out")
                Text("Status")
            }
            .font(.system(size: 18, weight: .medium))
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .background(AegisColors.tableHeader)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            if case .loading = state {
                TableMessage("Loading attendance...")
            } else if rows.isEmpty {
                TableMessage("No attendance data yet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            // Each row
                            LazyVGrid(columns: columns, spacing: 0) {
                                Text(row.name)
                                Text(row.session)
                                Text(formatDateTime(row.clockedInAt))
                                Text(formatDateTime(row.clockedOutAt))
                                Text(row.status.titleCasedStatus)
                                    .foregroundStyle(statusColor(row.status.titleCasedStatus))
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 64)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(AegisColors.rowDivider).frame(height: 1)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(minHeight: 130, maxHeight: .infinity)
            }

            if case let .failed(message) = state {
                ErrorBanner(message: message)
                    .padding(.top, 12)
            }
        }
    }
}
