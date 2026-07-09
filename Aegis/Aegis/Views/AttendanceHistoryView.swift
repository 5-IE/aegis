import SwiftUI

struct AttendanceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var selectedMonth: AttendanceMonthOption?
    @StateObject var viewModel = AttendanceHistoryViewModel()

    private var months: [AttendanceMonthOption] {
        viewModel.availableMonths
    }

    private var monthLabel: String {
        selectedMonth?.label ?? "No Data Available"
    }

    private var canMovePrevious: Bool {
        canMoveMonth(by: -1)
    }

    private var canMoveNext: Bool {
        canMoveMonth(by: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size:20,weight:.bold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Theme.cardBackground)
                        .clipShape(Circle())
                }
                Spacer()
                Text("Attendance History")
                    .font(.system(size: 22, weight:.semibold))
                    .foregroundColor(Theme.textInverse)
                Spacer()
                // invisible spacer to balance the back button
                Circle()
                    .frame(width: 40, height: 40)
                    .opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Month navigator
            HStack(spacing: 24) {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(Theme.textInverse.opacity(canMovePrevious ? 1 : 0.35))
                }
                .disabled(!canMovePrevious)
                Text(monthLabel)
                    .font(.system(size: 22, weight:.medium))
                    .foregroundColor(Theme.textInverse)
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(Theme.textInverse.opacity(canMoveNext ? 1 : 0.35))
                }
                .disabled(!canMoveNext)
            }
            .padding(.vertical, 10)

            // List
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.attendanceHistory.enumerated()), id: \.element.date) { index, record in
                        AttendanceRow(record: record)
                        if index < viewModel.attendanceHistory.count - 1 {
                            Divider()
                        }
                    }
                    .padding(.horizontal, 14)
                }

                .padding(.vertical, 10)
                .background(Theme.cardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Theme.cardShadow, radius: 18, x: 0, y: 8)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .background(
            LinearGradient(
                colors: [Theme.historyBackgroundStart, Theme.historyBackgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .task {
            await loadInitialData()
        }
    }

    private func changeMonth(by delta: Int) {
        guard canMoveMonth(by: delta), let targetMonth = monthOption(byAdding: delta) else { return }

        selectedMonth = targetMonth
        Task {
            await fetchSelectedMonth()
        }
    }

    private func canMoveMonth(by delta: Int) -> Bool {
        guard let targetMonth = monthOption(byAdding: delta) else { return false }
        return viewModel.hasAttendanceHistory(month: targetMonth.month, year: targetMonth.year)
    }

    private func monthOption(byAdding delta: Int) -> AttendanceMonthOption? {
        guard let selectedMonth else { return nil }

        var components = DateComponents()
        components.month = selectedMonth.month
        components.year = selectedMonth.year

        guard
            let date = Calendar.current.date(from: components),
            let targetDate = Calendar.current.date(byAdding: .month, value: delta, to: date)
        else { return nil }

        let targetComponents = Calendar.current.dateComponents([.month, .year], from: targetDate)
        guard let month = targetComponents.month, let year = targetComponents.year else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return AttendanceMonthOption(label: formatter.string(from: targetDate), month: month, year: year)
    }

    @MainActor
    private func loadInitialData() async {
        await viewModel.fetchAvailableMonths(store: store)
        selectDefaultMonth()
        await fetchSelectedMonth()
    }

    private func selectDefaultMonth() {
        guard !months.isEmpty else {
            selectedMonth = nil
            return
        }

        let currentDateComponents = Calendar.current.dateComponents([.month, .year], from: Date())
        if let currentMonth = months.first(where: {
            $0.month == currentDateComponents.month && $0.year == currentDateComponents.year
        }) {
            selectedMonth = currentMonth
        } else {
            selectedMonth = months.last
        }
    }

    @MainActor
    private func fetchSelectedMonth() async {
        guard let selectedMonth else { return }

        await viewModel.fetchAttendanceHistoryData(
            store: store,
            month: selectedMonth.month,
            year: selectedMonth.year
        )
    }
}

#Preview {
    NavigationStack { AttendanceHistoryView()
        .environment(DataStore(apiService: ApiService()))}
}
