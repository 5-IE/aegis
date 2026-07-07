import SwiftUI

struct AttendanceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var selectedMonthIndex: Int = 1
    @StateObject var viewModel = AttendanceHistoryViewModel()
    
    private let months: [(label: String, month: Int, year: Int)] = [
        ("May 2026", 5, 2026),
        ("June 2026", 6, 2026),
        ("July 2026", 7, 2026)
    ]

    private var monthLabel: String {
        months[selectedMonthIndex].label
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size:20,weight:.bold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                Spacer()
                Text("Attendance History")
                    .font(.system(size: 22, weight:.semibold))
                    .foregroundColor(.white)
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
                        .foregroundColor(.white)
                }
                Text(monthLabel)
                    .font(.system(size: 22, weight:.medium))
                    .foregroundColor(.white)
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white)
                }
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
                .shadow(color: Color.black.opacity(0.1), radius: 18, x: 0, y: 8)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)

                .task {
                    await fetchSelectedMonth()
                }
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
    }

    private func changeMonth(by delta: Int) {
        let newIndex = selectedMonthIndex + delta
        if months.indices.contains(newIndex) {
            selectedMonthIndex = newIndex
            Task {
                await fetchSelectedMonth()
            }
        }
    }

    @MainActor
    private func fetchSelectedMonth() async {
        let selectedMonth = months[selectedMonthIndex]
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
