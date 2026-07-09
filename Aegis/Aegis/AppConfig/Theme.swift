import SwiftUI

// MARK: - App Theme
// Centralized colors, fonts and spacing so every screen stays visually consistent.
enum Theme {
    // Brand
    static let primary = Color(hex: 0xA9C4CE)
    static let primaryDark = Color(hex: 0x49636B)

    // Backgrounds
    static let screenBackground = Color(lightHex: 0xFAFAFA, darkHex: 0x000000)
    static let historyBackgroundStart = Color(lightHex: 0x9BB6BF, darkHex: 0x1E3038)
    static let historyBackgroundEnd = Color(lightHex: 0xDBD5B2, darkHex: 0x2E2B1E)
    static let headerBackground = Color(lightHex: 0xA9C4CE, darkHex: 0x2A3E45)
    static let cardBackground = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)
    static let secondaryCardBackground = Color(lightHex: 0xFFFFFF, darkHex: 0x2C2C2E, lightOpacity: 0.85, darkOpacity: 0.85)

    // Text
    static let textPrimary = Color(lightHex: 0x000000, darkHex: 0xF2F2F7)
    static let textSecondary = Color(lightHex: 0x8E8E93, darkHex: 0xA0A0A5)
    static let textInverse = Color(hex: 0xFFFFFF)
    static let placeholderText = Color(lightHex: 0x8E8E93, darkHex: 0xA0A0A5)

    // Status
    static let onTime = Color(hex: 0x5BBF6E)
    static let onTimeBackground = Color(lightHex: 0xDBFBE9, darkHex: 0x1A3D26)
    static let late = Color(hex: 0xCFB20C)
    static let lateBackground = Color(lightHex: 0xF9F2C6, darkHex: 0x3D3A1A)
    static let leave = Color(hex: 0xEF4A4A)
    static let leaveBackground = Color(lightHex: 0xFFE9E9, darkHex: 0x3D1A1A)
    static let notCheckedIn = Color(hex: 0x3864BD)
    static let notCheckedInBackground = Color(lightHex: 0xE8F2FF, darkHex: 0x1A2A3D)
    static let absentBackground = Color(lightHex: 0xFFEDED, darkHex: 0x3D1A1A)

    // Today's attendance cards
    static let todayCheckedInBackground = Color(lightHex: 0xF1FFF6, darkHex: 0x0D2615)
    static let todayCheckedInFade = Color(hex: 0x408346)
    static let todayLateBackground = Color(lightHex: 0xFFFBE3, darkHex: 0x2E2B0D)
    static let todayLateFade = Color(hex: 0xE3C612)
    static let todayNotCheckedInBackground = Color(lightHex: 0xE8F2FF, darkHex: 0x0D1A2E)
    static let todayNotCheckedInFade = Color(hex: 0x5E76C4)
    static let todayLeaveBackground = Color(lightHex: 0xFFEDED, darkHex: 0x2E0D0D)
    static let todayLeaveFade = Color(hex: 0xC45E5E)

    // Shadows & Borders
    static let cardShadow = Color(lightHex: 0x000000, darkHex: 0x000000, lightOpacity: 0.12, darkOpacity: 0.30)
    static let border = Color(lightHex: 0x000000, darkHex: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.10)

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

extension Color {
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

extension Color {
    init(lightHex: UInt, darkHex: UInt, lightOpacity: Double = 1.0, darkOpacity: Double = 1.0) {
        self.init(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(Color(hex: darkHex, opacity: darkOpacity))
            } else {
                return UIColor(Color(hex: lightHex, opacity: lightOpacity))
            }
        })
    }
}
