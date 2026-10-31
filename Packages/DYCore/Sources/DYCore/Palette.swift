import Foundation
import simd

/// The one source of colour for renderers and UI. All values are sRGB in 0...1.
///
/// The seven kind hues passed the dataviz validator on `background`, all pairs: CVD ΔE at least 8.0, normal vision
/// at least 15. Video and audio sit at 2.9:1 contrast, so tiles must carry labels, which is already a design rule.
/// Archives are khaki rather than gold, so in Kind mode nothing competes with the accent.
/// Gold is reserved for "reclaimable", which is the product's central visual idea.
public enum Palette {
    /// Builds a colour from a 24-bit hex value.
    public static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    public static let background = rgb(0x0E0D0B)
    public static let surface = rgb(0x171613)
    public static let surfaceRaised = rgb(0x211F1B)
    public static let hairline = rgb(0x2E2B26)
    public static let textPrimary = rgb(0xF3EFE6)
    public static let textSecondary = rgb(0xB5AFA3)
    public static let textMuted = rgb(0x7D786E)

    /// The brand accent: deep yellow, reserved for what can be reclaimed and for focus.
    public static let accent = rgb(0xFFB800)

    /// Staged for removal. Always paired with a hatch pattern, never colour alone.
    public static let remove = rgb(0xFF5A4F)
    /// Protected. Always paired with a pin glyph.
    public static let keep = rgb(0x3DDC97)
    /// Deferred. Always paired with a dot glyph.
    public static let later = rgb(0x8FA3FF)

    /// The fill for a file category.
    public static func kind(_ kind: FileKind) -> SIMD3<Float> {
        switch kind {
        case .video: rgb(0x934350)
        case .image: rgb(0xDA5E85)
        case .audio: rgb(0x7E3DB0)
        case .document: rgb(0x5277F7)
        case .code: rgb(0x388100)
        case .application: rgb(0x27A4BD)
        case .archive: rgb(0x9D9138)
        case .other: rgb(0x6E6A62)
        }
    }

    /// The fill for a safety tier in safety colour mode. Only gold tiers draw the eye; the rest recede.
    public static func safety(_ tier: SafetyTier) -> SIMD3<Float> {
        switch tier {
        case .safe: accent
        case .rebuild: rgb(0xB97F12)
        case .review: rgb(0x4A463F)
        case .never: rgb(0x1F1D1A)
        case .unknown: rgb(0x34312B)
        }
    }

    /// A single-hue age ramp: recent is dark and recedes, old is bright gold because it's the likelier candidate.
    /// - Parameter age: Age in seconds. Mapped on a log scale from one day to five years.
    public static func age(seconds age: Int32) -> SIMD3<Float> {
        let low = log(Float(86_400)), high = log(Float(86_400 * 365 * 5))
        let t = simd_clamp((log(max(Float(age), 1)) - low) / (high - low), 0, 1)
        return simd_mix(rgb(0x2A2822), accent, SIMD3(repeating: t))
    }
}
