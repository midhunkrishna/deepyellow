import DYCore
import DYLenses
import SwiftUI

/// A keyboard key drawn as a small cap.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.hairline, lineWidth: 1))
    }
}

/// A compact text button, optionally with a key cap and a tint for decisions.
struct ChipButton: View {
    let title: String
    var key: String?
    var tint: Color?
    var prominent = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 11.5, weight: .medium))
                if let key { KeyCap(text: key) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(prominent ? Color.black : (tint ?? Theme.textPrimary))
            .background(prominent ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(prominent ? Color.clear : Theme.hairline, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Diagonal stripes, used wherever "staged for removal" is drawn so it is never colour alone.
struct Hatch: View {
    var color: Color = Theme.remove
    var spacing: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1.2)
        }
    }
}

/// A centred card over a dimmed window. Clicking outside it closes it.
struct ModalPanel<Content: View>: View {
    let width: CGFloat
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture(perform: close)
            content()
                .frame(width: width)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
    }
}

/// A usage bar: used share of a volume.
struct UsageBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule().fill(Theme.textSecondary).frame(width: max(2, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// A decision glyph: hatch for remove, pin for keep, dot for later. State is never colour alone.
struct DecisionGlyph: View {
    let decision: Decision

    var body: some View {
        switch decision {
        case .remove: Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.remove)
        case .keep: Image(systemName: "pin.fill").foregroundStyle(Theme.keep)
        case .later: Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Theme.later)
        case .none: EmptyView()
        }
    }
}

/// A short name for a decision.
func decisionName(_ decision: Decision) -> String {
    switch decision {
    case .none: "undecided"
    case .keep: "keep"
    case .remove: "remove"
    case .later: "later"
    }
}

/// A short name for a safety tier, as shown to people.
func tierName(_ tier: SafetyTier) -> String {
    switch tier {
    case .unknown: "no advice"
    case .safe: "safe"
    case .rebuild: "rebuilds itself"
    case .review: "look first"
    case .never: "never remove"
    }
}
