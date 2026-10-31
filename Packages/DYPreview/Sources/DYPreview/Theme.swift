import DYCore
import SwiftUI

/// Converts palette values to SwiftUI colours.
enum Theme {
    /// Builds a colour from a palette value.
    static func color(_ v: SIMD3<Float>) -> Color { Color(.sRGB, red: Double(v.x), green: Double(v.y), blue: Double(v.z)) }
    static let background = color(Palette.background)
    static let surface = color(Palette.surface)
    static let hairline = color(Palette.hairline)
    static let primary = color(Palette.textPrimary)
    static let secondary = color(Palette.textSecondary)
    static let muted = color(Palette.textMuted)
    static let accent = color(Palette.accent)
}
