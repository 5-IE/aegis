import SwiftUI

enum AegisColors {
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let mutedText = Color(red: 0.42, green: 0.45, blue: 0.46)
    static let teal = Color(red: 0.30, green: 0.42, blue: 0.45)
    static let tealDark = Color(red: 0.24, green: 0.36, blue: 0.39)
    static let tableHeader = Color(red: 0.70, green: 0.82, blue: 0.85)
    static let dashboardBackground = Color(red: 0.985, green: 0.985, blue: 0.985)
    static let surface = Color.white.opacity(0.94)
    static let surfaceAlt = Color.white.opacity(0.78)
    static let panelBorder = Color.black.opacity(0.08)
    static let cardShadow = Color.black.opacity(0.16)
    static let rowDivider = Color.black.opacity(0.08)
    static let activeGreen = Color(red: 0.24, green: 0.70, blue: 0.25)
    static let inactiveYellow = Color(red: 0.77, green: 0.68, blue: 0.20)
    static let beaconBlue = Color(red: 0.29, green: 0.31, blue: 0.58)

    static var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.70, green: 0.84, blue: 0.88),
                    Color(red: 0.88, green: 0.92, blue: 0.86),
                    Color(red: 0.72, green: 0.86, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.52), Color.white.opacity(0.04)],
                center: .center,
                startRadius: 70,
                endRadius: 700
            )
            RadialGradient(
                colors: [Color(red: 0.78, green: 0.86, blue: 0.65).opacity(0.32), .clear],
                center: .bottomTrailing,
                startRadius: 70,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}


enum AegisTypography {
    static let h1 = Font.system(size: 36, weight: .bold)
    static let h2 = Font.system(size: 22, weight: .semibold)
    static let h3 = Font.system(size: 20, weight: .semibold)
    static let b1 = Font.system(size: 20, weight: .medium)
    static let b2 = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 14, weight: .medium)
}

enum AegisSpacing {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 16
    static let medium: CGFloat = 20
    static let section: CGFloat = 24
    static let large: CGFloat = 32
    static let screenTop: CGFloat = 40
}

struct AegisCard<Content: View>: View {
    var padding: CGFloat = AegisSpacing.medium
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(AegisColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AegisColors.panelBorder, lineWidth: 1)
            }
            .shadow(color: AegisColors.cardShadow, radius: 5, x: 0, y: 2)
    }
}

struct AegisPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(AegisColors.teal.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WhitePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        AegisCard(padding: AegisSpacing.medium) {
            content
        }
    }
}

struct DateChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar")
            Text(text)
            Image(systemName: "chevron.down")
        }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.black)
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(AegisColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.gray)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}

struct MetricIcon: View {
    let symbol: String
    let color: Color
    let background: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)
    }
}

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(iconBackground.opacity(0.90))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 23)
        .frame(height: 104)
        .background(AegisColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AegisColors.panelBorder, lineWidth: 1)
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10, weight: .bold))
        }
    }
}

struct TableHeader: View {
    let columns: [(String, CGFloat)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column.0)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(
                        minWidth: column.1 == .infinity ? 0 : column.1,
                        maxWidth: column.1 == .infinity ? .infinity : column.1,
                        alignment: .leading
                    )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AegisColors.tableHeader)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TableMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(AegisTypography.b2)
            .foregroundStyle(AegisColors.mutedText)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0.72, green: 0.12, blue: 0.12))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1.0, green: 0.92, blue: 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct FormTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AegisColors.mutedText)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SecureFormField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AegisColors.mutedText)
            SecureField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

extension View {
    func aegisH1() -> some View {
        self
            .font(AegisTypography.h1)
            .foregroundStyle(.black)
    }

    func aegisH2() -> some View {
        self
            .font(AegisTypography.h2)
            .foregroundStyle(.black)
    }

    func aegisH3() -> some View {
        self
            .font(AegisTypography.h3)
            .foregroundStyle(.black)
    }

    func aegisB1() -> some View {
        self
            .font(AegisTypography.b1)
            .foregroundStyle(.black)
    }

    func aegisB2() -> some View {
        self
            .font(AegisTypography.b2)
            .foregroundStyle(.black)
    }

    func screenTitle() -> some View {
        self
            .font(AegisTypography.h1)
            .foregroundStyle(.black)
    }

    func screenPadding() -> some View {
        self
            .padding(.top, 40)
            .padding(.leading, 40)
            .padding(.trailing, 32)
            .padding(.bottom, 32)
    }

    func tableCell(width: CGFloat? = nil, maxWidth: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        self
            .font(AegisTypography.b2)
            .lineLimit(1)
            .frame(
                minWidth: width ?? 0,
                maxWidth: maxWidth ?? width ?? .infinity,
                alignment: alignment
            )
            .padding(.horizontal, 16)
    }
}

func statusColor(_ status: String) -> Color {
    let lowered = status.lowercased()
    if lowered.contains("active") || lowered.contains("on time") || lowered.contains("checked in") || lowered.contains("early") {
        return AegisColors.activeGreen
    }
    if lowered.contains("late") || lowered.contains("running") {
        return AegisColors.inactiveYellow
    }
    return AegisColors.mutedText
}

func formatDateTime(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "-" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fallback = ISO8601DateFormatter()
    let date = formatter.date(from: iso) ?? fallback.date(from: iso)
    guard let date else { return iso }
    let output = DateFormatter()
    output.dateFormat = "HH:mm"
    return output.string(from: date)
}
