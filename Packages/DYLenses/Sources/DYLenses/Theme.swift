import DYCore
import SwiftUI

/// SwiftUI colours and type shared by every view. Values come only from `Palette`.
public enum Theme {
    /// Converts a palette colour to a SwiftUI colour.
    public static func color(_ value: SIMD3<Float>) -> Color {
        Color(.sRGB, red: Double(value.x), green: Double(value.y), blue: Double(value.z), opacity: 1)
    }

    public static let background = color(Palette.background)
    public static let surface = color(Palette.surface)
    public static let surfaceRaised = color(Palette.surfaceRaised)
    public static let hairline = color(Palette.hairline)
    public static let textPrimary = color(Palette.textPrimary)
    public static let textSecondary = color(Palette.textSecondary)
    public static let textMuted = color(Palette.textMuted)
    public static let accent = color(Palette.accent)
    public static let remove = color(Palette.remove)
    public static let keep = color(Palette.keep)
    public static let later = color(Palette.later)

    /// The fill for a file category.
    public static func kind(_ kind: FileKind) -> Color { color(Palette.kind(kind)) }

    /// A number in the interface's tabular style, so columns of sizes line up.
    public static func number(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Monospaced detail text, used for paths, commands and queries.
    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
