import CoreGraphics
import DYCore

/// Which item an arrow key lands on. Pure, so it can be tested without a window.
public enum LevelNavigation {
    /// The next item in a list: right and down go forward, left and up go back. Nil at either end.
    public static func next(from current: NodeID, _ direction: MoveDirection, in items: [NodeID]) -> NodeID? {
        guard let index = items.firstIndex(of: current) else { return nil }
        let target = index + (direction == .right || direction == .down ? 1 : -1)
        return items.indices.contains(target) ? items[target] : nil
    }

    /// The tile that sits next to `current` on the map in `direction`, or nil when nothing lies that way.
    public static func tile(from current: NodeID, _ direction: MoveDirection, rects: [NodeID: CGRect]) -> NodeID? {
        guard let here = rects[current] else { return nil }
        var best: (node: NodeID, score: CGFloat)?
        for (node, rect) in rects where node != current {
            guard let score = distance(to: rect, from: here, direction) else { continue }
            if best == nil || score < best!.score || (score == best!.score && node < best!.node) { best = (node, score) }
        }
        return best?.node
    }

    /// How far `rect` is from `here` going `direction`, or nil when it isn't that way. Lower is closer.
    ///
    /// A tile straight ahead beats one off to the side, and among those the one most in line with `here` wins.
    private static func distance(to rect: CGRect, from here: CGRect, _ direction: MoveDirection) -> CGFloat? {
        let gap: CGFloat
        let sideways: CGFloat
        let misalignment: CGFloat
        switch direction {
        case .left, .right:
            gap = direction == .right ? rect.minX - here.maxX : here.minX - rect.maxX
            sideways = max(0, rect.minY - here.maxY, here.minY - rect.maxY)
            misalignment = abs(rect.midY - here.midY)
        case .up, .down:
            gap = direction == .down ? rect.minY - here.maxY : here.minY - rect.maxY
            sideways = max(0, rect.minX - here.maxX, here.minX - rect.maxX)
            misalignment = abs(rect.midX - here.midX)
        }
        guard gap >= -1e-9 else { return nil }
        return max(gap, 0) + sideways * 3 + misalignment * 0.01
    }
}
