import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var sessionStore: SessionStore

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
                            .frame(height: 64)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(AegisColors.rowDivider).frame(height: 1)
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
