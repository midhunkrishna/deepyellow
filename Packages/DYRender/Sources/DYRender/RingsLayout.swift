import DYCore
import Foundation

/// One annular sector of the sunburst. Angles run clockwise from the top, in radians.
public struct RingArc {
    public var node: NodeID
    public var parent: NodeID
    public var depth: Int
    public var start: Double, end: Double
    public var value: UInt64
    /// A dust arc stands for every small child of `parent` that did not get its own arc.
    public var isDust: Bool
    public var dustFiles: UInt64 = 0, dustBytes: UInt64 = 0
    public var isDirectory: Bool
    public var span: Double { end - start }
}

/// Pure sunburst layout: which arcs exist and where, with no drawing.
public enum RingsLayout {
    public static let levels = 5
    /// Arcs thinner than this (about 0.7 degrees) fold into the parent's dust arc.
    public static let minimumAngle = 0.012
    public static let maximumChildren = 48
    public static let topAngle = -Double.pi / 2

    /// Lays out `levels` rings of descendants of `root`, which fills the full circle. Arcs come in angular order per depth.
    public static func arcs(lens: TreeLens, metric: Metric, root: NodeID, levels: Int = RingsLayout.levels) -> [RingArc] {
        var result: [RingArc] = []
        expand(lens: lens, metric: metric, node: root, start: topAngle, end: topAngle + 2 * Double.pi, depth: 0, levels: levels, into: &result)
        return result
    }

    /// Lays out one node's children inside its angular span, then recurses into directories.
    private static func expand(lens: TreeLens, metric: Metric, node: NodeID, start: Double, end: Double, depth: Int, levels: Int,
                               into result: inout [RingArc]) {
        guard depth < levels else { return }
        let children = lens.visibleChildren(of: node, metric: metric)
        let total = children.reduce(UInt64(0)) { $0 &+ lens.value($1, metric) }
        guard total > 0 else { return }
        var cursor = start, consumed: UInt64 = 0, taken = 0
        for (index, child) in children.enumerated() {
            let value = lens.value(child, metric)
            let angle = (end - start) * Double(value) / Double(total)
            if angle < minimumAngle || index >= maximumChildren { break }
            let isDirectory = lens.tree.columns.childCount[Int(child)] > 0
            result.append(RingArc(node: child, parent: node, depth: depth, start: cursor, end: cursor + angle, value: value,
                                  isDust: false, isDirectory: isDirectory))
            if isDirectory { expand(lens: lens, metric: metric, node: child, start: cursor, end: cursor + angle, depth: depth + 1, levels: levels, into: &result) }
            cursor += angle
            consumed &+= value
            taken += 1
        }
        if consumed < total {
            let rest = children.dropFirst(taken)
            let bytes = rest.reduce(UInt64(0)) { $0 &+ lens.size[Int($1)] }
            let files = rest.reduce(UInt64(0)) { $0 &+ UInt64(lens.files[Int($1)]) }
            result.append(RingArc(node: node, parent: node, depth: depth, start: cursor, end: end, value: total - consumed, isDust: true,
                                  dustFiles: files, dustBytes: bytes, isDirectory: false))
        }
    }
}

/// Where the rings sit in a view: centre, hole and the radius of every ring edge.
public struct RingsGeometry {
    public var centre: SIMD2<Double>
    /// `levels + 1` radii: the hole's edge, then the outer edge of each ring.
    public var edges: [Double]

    /// Fits the rings inside `viewPx`, leaving `margin` pixels around.
    public init(viewPx: SIMD2<Double>, margin: Double, levels: Int = RingsLayout.levels) {
        centre = viewPx / 2
        let outer = max(min(viewPx.x, viewPx.y) / 2 - margin, 40)
        let hole = outer * 0.25
        let weights = [1.25, 1.05, 0.95, 0.85, 0.75, 0.7].prefix(levels)
        let unit = (outer - hole) / weights.reduce(0, +)
        var radius = hole
        edges = [hole] + weights.map { radius += $0 * unit; return radius }
    }

    public var hole: Double { edges[0] }

    /// The ring depth and clockwise-from-top angle for a pixel, or nil outside the rings.
    public func locate(_ point: SIMD2<Double>) -> (depth: Int, angle: Double)? {
        let d = point - centre
        let r = (d.x * d.x + d.y * d.y).squareRoot()
        guard r >= edges[0], r < edges[edges.count - 1] else { return nil }
        let depth = edges.dropFirst().firstIndex { r < $0 }.map { $0 - 1 } ?? edges.count - 2
        var angle = atan2(d.y, d.x) - RingsLayout.topAngle
        angle -= 2 * Double.pi * (angle / (2 * Double.pi)).rounded(.down)
        return (depth, angle)
    }
}
