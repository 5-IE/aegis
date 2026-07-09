import SwiftUI

// MARK: - Adaptive Color Initializer

extension Color {
    /// Creates a color that adapts between light and dark appearance on macOS.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(dark)
            } else {
                return NSColor(light)
            }
        }))
    }
}

// MARK: - Adaptive Tokens

extension AegisColors {
    static let text = Color(
        light: Color(red: 0.04, green: 0.05, blue: 0.06),
        dark: Color(red: 0.95, green: 0.95, blue: 0.97)
    )

    static let textSecondary = Color(
        light: Color(red: 0.42, green: 0.45, blue: 0.46),
        dark: Color(red: 0.62, green: 0.64, blue: 0.66)
    )

    static let surfaceSolid = Color(
        light: .white,
        dark: Color(red: 0.11, green: 0.11, blue: 0.12)
    )

    static let inputBackground = Color(
        light: .white,
        dark: Color(red: 0.17, green: 0.17, blue: 0.18)
    )

    static let loginBackground = Color(
        light: .white,
        dark: Color(red: 0.11, green: 0.11, blue: 0.12)
    )

    static let border = Color(
        light: Color(nsColor: NSColor.black.withAlphaComponent(0.08)),
        dark: Color(nsColor: NSColor.white.withAlphaComponent(0.10))
    )

    static let adaptiveCardShadow = Color(
        light: Color(nsColor: NSColor.black.withAlphaComponent(0.16)),
        dark: Color(nsColor: NSColor.black.withAlphaComponent(0.30))
    )

    static let tableHeaderBg = Color(
        light: Color(red: 0.70, green: 0.82, blue: 0.85),
        dark: Color(red: 0.20, green: 0.28, blue: 0.30)
    )
}

// MARK: - Adaptive App Background

struct AdaptiveAppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            darkBackground
        } else {
            lightBackground
        }
    }

    private var lightBackground: some View {
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
    }

    private var darkBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.14),
                    Color(red: 0.12, green: 0.13, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.18, green: 0.24, blue: 0.26).opacity(0.18), .clear],
                center: .center,
                startRadius: 70,
                endRadius: 700
            )
            RadialGradient(
                colors: [Color(red: 0.16, green: 0.22, blue: 0.18).opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 70,
                endRadius: 500
            )
        }
    }
}
