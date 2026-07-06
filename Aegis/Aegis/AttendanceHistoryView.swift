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
                    ForEach(Array(SampleData.juneHistory.enumerated()), id: \.element.id) { index, record in
                        AttendanceRow(record: record)
                            .padding(.horizontal, 22)

                        if index < SampleData.juneHistory.count - 1 {
                            Divider()
                        }
                    }
                }

                .padding(.vertical, 10)
                .background(Theme.cardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 8)
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
