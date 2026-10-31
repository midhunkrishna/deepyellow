import DYCore
import SwiftUI

/// A small rounded label for a safety tier. The words carry the meaning; the colour only supports them.
struct TierPill: View {
    let tier: SafetyTier

    /// The label shown for a tier, or nil when no advice applies.
    static func title(_ tier: SafetyTier) -> String? {
        switch tier {
        case .safe: "Safe"
        case .rebuild: "Recoverable"
        case .review: "Look first"
        case .never: "Not offered"
        case .unknown: nil
        }
    }

    var body: some View {
        if let title = Self.title(tier) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 1)
                .foregroundStyle(ink)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(tier == .never ? Theme.hairline : .clear, lineWidth: 1))
        }
    }

    private var fill: Color {
        switch tier {
        case .safe: Theme.accent
        case .rebuild: Color(.sRGB, red: 0x5A / 255, green: 0x3F / 255, blue: 0x0B / 255)
        case .review: Theme.surfaceRaised
        default: Theme.background
        }
    }

    private var ink: Color {
        switch tier {
        case .safe: Theme.background
        case .rebuild: Color(.sRGB, red: 1, green: 0xD9 / 255, blue: 0x8A / 255)
        default: Theme.textSecondary
        }
    }
}

/// Diagonal stripes, the mark for "staged for removal". Never colour alone.
struct HatchFill: View {
    var color: Color = Theme.remove
    var spacing: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 1.2)
        }
    }
}

/// The glyph for a decision: remove is hatched, keep has a check, later has a dot.
struct DecisionGlyph: View {
    let decision: Decision
    var size: CGFloat = 12

    var body: some View {
        switch decision {
        case .remove:
            HatchFill(spacing: 3.5)
                .frame(width: size, height: size)
                .background(Theme.remove.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.remove, lineWidth: 1))
        case .keep:
            Image(systemName: "checkmark").font(.system(size: size - 1, weight: .bold)).foregroundStyle(Theme.keep)
                .frame(width: size, height: size)
        case .later:
            Circle().fill(Theme.later).frame(width: size * 0.62, height: size * 0.62).frame(width: size, height: size)
        case .none:
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// A decision's glyph and word together, for rows.
struct DecisionTag: View {
    let decision: Decision

    /// The word for a decision.
    static func title(_ decision: Decision) -> String {
        switch decision {
        case .remove: "Remove"
        case .keep: "Keep"
        case .later: "Later"
        case .none: ""
        }
    }

    /// The text colour for a decision.
    static func ink(_ decision: Decision) -> Color {
        switch decision {
        case .remove: Theme.remove
        case .keep: Theme.keep
        case .later: Theme.later
        case .none: Theme.textMuted
        }
    }

    var body: some View {
        if decision != .none {
            HStack(spacing: 4) {
                DecisionGlyph(decision: decision, size: 11)
                Text(Self.title(decision)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Self.ink(decision))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The small kind swatch used beside names.
struct KindSwatch: View {
    let kind: FileKind

    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(Theme.kind(kind)).frame(width: 10, height: 10)
    }
}

/// A quiet outlined button for secondary actions.
struct GhostButtonStyle: ButtonStyle {
    var ink: Color = Theme.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(configuration.isPressed ? Theme.textPrimary : ink)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Theme.surfaceRaised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The one gold call to action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(Theme.background)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

/// A key cap, such as the `k` beside Keep.
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(Theme.mono(size: 11))
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 18)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// The title and one explanatory line at the top of a lens.
struct LensHeadline: View {
    let title: Text
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            title.font(.system(size: 22, weight: .semibold)).tracking(-0.3).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A centred message for a lens that has nothing to show yet.
struct LensPlaceholder: View {
    let message: String

    var body: some View {
        Text(message).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Formats a metric value: bytes as a size, files as a count.
enum MetricFormat {
    /// "4.21 GB" or "12,431 files".
    static func text(_ value: UInt64, metric: Metric) -> String {
        metric == .bytes ? Format.bytes(value) : "\(Format.count(value)) files"
    }
}
