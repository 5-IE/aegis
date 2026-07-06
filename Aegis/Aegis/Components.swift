import SwiftUI

// MARK: - Status Badge (e.g. "On-time", "Late", "Leave")
struct StatusBadge: View {
    let status: AttendanceStatus
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon ?? defaultIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(status.color)
            Text(status.rawValue)
                .font(Theme.Fonts.b2)
                .foregroundColor(status.color)
                .frame(width: 54, alignment:.center)
        }
        .frame(width: 78, height: 23)
        .background(status.backgroundColor)
        .clipShape(Capsule())
    }

    private var defaultIcon: String {
        switch status {
        case .onTime:
            return "checkmark.circle.fill"
        case .late:
            return "clock.fill"
        case .leave:
            return "xmark.circle.fill"
        }
    }
}

// MARK: - Stat Card (used in the 3-up summary row on the Home screen)
struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Theme.statisticsIcon)
            Text(value)
                .font(Theme.Fonts.h1)
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(Theme.Fonts.b2)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
    }
}

// MARK: - Attendance Row (used in both Home and Attendance History lists)
struct AttendanceRow: View {
    let record: AttendanceRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.dateLabel)
                    .font(Theme.Fonts.b1)
                    .foregroundColor(Theme.textPrimary)
                Text(record.timeRange)
                    .font(Theme.Fonts.b2)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            StatusBadge(status: record.status)
        }
        .frame(minHeight: 54)
        .padding(.vertical, 4)
    }
}

// MARK: - Today's Attendance Card
struct TodayAttendanceCard: View {
    let status: TodayAttendanceStatus

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            TodayAttendanceStatusIcon(status: status)

            VStack(alignment: .leading, spacing: 8) {
                Text(status.title)
                    .font(Theme.Fonts.h2)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(status.message)
                    .font(Theme.Fonts.b2)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)

                Text(status.detail)
                    .font(Theme.Fonts.b2)
                    .foregroundColor(status.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)

            TodayAttendanceIllustration(status: status)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(height: 95)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            status.backgroundColor,
                            status.backgroundColor.opacity(0.72),
                            Theme.cardBackground.opacity(0.9)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(status.accentColor.opacity(0.18))
                        .frame(width: 88, height: 88)
                        .blur(radius: 16)
                        .offset(x: 18)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 3)
    }
}

struct TodayAttendanceGrid: View {
    let statuses: [TodayAttendanceStatus]
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(statuses) { status in
                TodayAttendanceCard(status: status)
            }
        }
    }
}

private struct TodayAttendanceStatusIcon: View {
    let status: TodayAttendanceStatus

    var body: some View {
                Image(systemName: status.statusIcon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(status.accentColor)
            
    }
}

private struct TodayAttendanceIllustration: View {
    let status: TodayAttendanceStatus

    var body: some View {
        Image(status.illustrationAsset)
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 120)
            .accessibilityHidden(true)
    }
}

// MARK: - Primary Button (Sign In, etc.)
struct PrimaryButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.primary)
                .cornerRadius(Theme.fieldCornerRadius)
        }
    }
}

// MARK: - Secondary (outline) Button
struct SecondaryButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.fieldCornerRadius)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

// MARK: - Icon Text Field (email / password style input used on Login)
struct IconTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 18)
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.fieldCornerRadius)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview("Today's Attendance States") {
    ScrollView {
        TodayAttendanceGrid(statuses: SampleData.todayAttendanceOptions)
            .padding(20)
    }
    .background(Theme.screenBackground)
}
