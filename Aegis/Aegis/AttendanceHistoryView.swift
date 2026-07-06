import SwiftUI

struct AttendanceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentMonthIndex: Int = 0
    private let months = ["May 2026", "June 2026", "July 2026"]

    private var monthLabel: String {
        months[1 + currentMonthIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                }
                Spacer()
                Text("Attendance History")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                // invisible spacer to balance the back button
                Image(systemName: "chevron.left").opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Month navigator
            HStack(spacing: 24) {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(Theme.primary)
                }
                Text(monthLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.primary)
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(Theme.primary)
                }
            }
            .padding(.vertical, 10)

            // List
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(SampleData.juneHistory.enumerated()), id: \.element.id) { index, record in
                        AttendanceRow(record: record)
                            .padding(.horizontal, 20)
                        if index < SampleData.juneHistory.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private func changeMonth(by delta: Int) {
        let newIndex = currentMonthIndex + delta
        if newIndex >= -1 && newIndex <= 1 {
            currentMonthIndex = newIndex
        }
    }
}

#Preview {
    NavigationStack { AttendanceHistoryView() }
}
