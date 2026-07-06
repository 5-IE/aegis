import SwiftUI

struct HomeView: View {
    let userName: String = "Dhita"
    let todayLabel: String = "Mon, 29 Jun 2026"
    let checkedInTime: String = "12:55PM"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Greeting header
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.86, blue: 0.88))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hi, \(userName)")
                            .font(.title3.bold())
                            .foregroundColor(Theme.textPrimary)
                        Text(todayLabel)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                }

                // Stat cards
                HStack(spacing: 12) {
                    StatCard(value: "84", label: "Total Attendance", icon: "person.2.fill")
                    StatCard(value: "02", label: "Total Late", icon: "clock.badge.exclamationmark.fill")
                    StatCard(value: "01", label: "Leave Taken", icon: "calendar.badge.minus")
                }

                // Today's Attendance
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's Attendance")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.onTime)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Checked In!")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text("You're all set for today.")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            Text("Checked in at \(checkedInTime)")
                                .font(.caption.weight(.medium))
                                .foregroundColor(Theme.onTime)
                        }

                        Spacer()

                        Text("👍")
                            .font(.largeTitle)
                    }
                    .padding(16)
                    .background(Theme.onTimeBackground)
                    .cornerRadius(Theme.cornerRadius)
                }

                // Attendance History (recent)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Attendance History")
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        NavigationLink("See All") {
                            AttendanceHistoryView()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Theme.primary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(SampleData.recentAttendance.enumerated()), id: \.element.id) { index, record in
                            AttendanceRow(record: record)
                            if index < SampleData.recentAttendance.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadius)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
            }
            .padding(20)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

#Preview {
    NavigationStack { HomeView() }
}
