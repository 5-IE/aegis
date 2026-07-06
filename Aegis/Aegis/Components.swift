import SwiftUI

// MARK: - Status Badge (e.g. "On-time", "Late", "Leave")
struct StatusBadge: View {
    let status: AttendanceStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(status.backgroundColor)
        .clipShape(Capsule())
    }
}

// MARK: - Stat Card (used in the 3-up summary row on the Home screen)
struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(Theme.statisticsIcon)
            Text(value)
                .font(.title2.bold())
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Attendance Row (used in both Home and Attendance History lists)
struct AttendanceRow: View {
    let record: AttendanceRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.dateLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(record.timeRange)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            StatusBadge(status: record.status)
        }
        .padding(.vertical, 12)
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
