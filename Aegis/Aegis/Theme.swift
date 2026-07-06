import SwiftUI

// MARK: - App Theme
// Centralized colors, fonts and spacing so every screen stays visually consistent.
enum Theme {
    // Brand
    static let primary = Color(hex: 0xA9C4CE)
    static let primaryDark = Color(hex: 0x49636B)

    // Backgrounds
    static let screenBackground = Color(hex: 0xFAFAFA)
    static let historyBackgroundStart = Color(hex: 0x9BB6BF)
    static let historyBackgroundEnd = Color(hex: 0xDBD5B2)
    static let headerBackground = Color(hex: 0xA9C4CE)
    static let cardBackground = Color(hex: 0xFFFFFF)
    static let secondaryCardBackground = Color(hex: 0xFFFFFF).opacity(0.85)

    // Text
    static let textPrimary = Color(hex: 0x000000)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let textInverse = Color(hex: 0xFFFFFF)
    static let placeholderText = Color(hex: 0x8E8E93)

    // Status
    static let onTime = Color(hex: 0x5BBF6E)
    static let onTimeBackground = Color(hex: 0xDBFBE9)
    static let late = Color(hex: 0xCFB20C)
    static let lateBackground = Color(hex: 0xF9F2C6)
    static let leave = Color(hex: 0xEF4A4A)
    static let leaveBackground = Color(hex: 0xFFE9E9)
    static let notCheckedIn = Color(hex: 0x3864BD)
    static let notCheckedInBackground = Color(hex: 0xE8F2FF)
    static let absentBackground = Color(hex: 0xFFEDED)

    // Shape
    static let cornerRadius: CGFloat = 16
    static let fieldCornerRadius: CGFloat = 12

    // Typography
    enum Fonts {
        static let h1 = Font.system(size: 30, weight: .bold)
        static let h2 = Font.system(size: 16, weight: .bold)
        static let b1 = Font.system(size: 14, weight: .semibold)
        static let b2 = Font.system(size: 12, weight: .regular)
        static let statIcons = Font.system(size: 20, weight: .regular)
        static let badgeIcons = Font.system(size: 30, weight:.regular)
    }

    // Symbols
    static let statisticsIcon = Color(hex: 0xA9C4CE)
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
