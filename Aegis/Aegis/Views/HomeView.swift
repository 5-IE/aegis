import SwiftUI

struct HomeView: View {
    @Environment(DataStore.self) private var dataStore
    @StateObject var viewModel = HomeViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            Theme.screenBackground
                .ignoresSafeArea()

            Theme.headerBackground
                .frame(height: 228)
                .ignoresSafeArea(edges: .top)
 
            VStack(alignment: .leading, spacing: 24) {
 
                // Greeting header
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.72, green: 0.74, blue: 0.74))
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hi, \(viewModel.currentUser?.firstName ?? "Learner")")
                            .font(Theme.Fonts.h1)
                            .foregroundColor(Theme.textPrimary)
                        Text(viewModel.todayLabel)
                            .font(Theme.Fonts.b2)
                            .foregroundColor(Theme.primaryDark)
                    }
                    Spacer()
                    Button {
                        dataStore.signOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
 
                // Stat cards
                HStack(spacing: 0) {
                    StatCard(value: viewModel.totalAttendance, label: "Total Attendance", icon: "person.2.fill")
                    Divider().frame(height: 54)
                    StatCard(value: viewModel.totalLate, label: "Total Late", icon: "clock.badge.exclamationmark.fill")
                    Divider().frame(height: 54)
                    StatCard(value: viewModel.leaveTaken, label: "Leave Taken", icon: "calendar.badge.minus")
                }
                .background(Theme.cardBackground)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
 
                // Today's Attendance
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's Attendance")
                        .font(Theme.Fonts.h2)
                        .foregroundColor(Theme.textPrimary)
 
                    TodayAttendanceCard(status: viewModel.todayStatus)
                }
 
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Attendance History")
                            .font(Theme.Fonts.h2)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        NavigationLink {
                            AttendanceHistoryView()
                        } label: {
                            HStack(spacing: 4) {
                                Text("See All")
                                    .font(Theme.Fonts.b2)
                                Image(systemName: "chevron.right")
                                    .font(Theme.Fonts.b2)
                            }
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.cardBackground)
                            .clipShape(Capsule())
                        }
                    }
 
                    VStack(spacing: 4) {
                        ForEach(Array(viewModel.attendanceHistory.enumerated()), id: \.element.date) { index, record in
                            AttendanceRow(record: record)
                            if index < viewModel.attendanceHistory.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackground)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 24)
            .padding(.bottom, 24)
            
            VStack() {
                if let errorMessage = viewModel.errorMessage {
                    Button(action: {
                        viewModel.errorMessage = nil
                    }) {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8).cornerRadius(Theme.cornerRadius))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.requestData(dataStore: dataStore)
        }
    }
}

#Preview {
    NavigationStack { HomeView()
        .environment(DataStore(apiService: ApiService()))}
}

