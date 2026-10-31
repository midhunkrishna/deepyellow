import Foundation

/// An axis-aligned rectangle in double precision. Used for world-space layout, where deep zoom needs more than Float.
public struct WRect: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double

    /// Creates a rectangle from its origin and size.
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var area: Double { w * h }
    public var minSide: Double { min(w, h) }

    /// Whether the point lies inside, edges included on the low side only.
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < maxX && py >= y && py < maxY }

    /// Whether `other` lies inside this rectangle within `tolerance`.
    public func contains(_ other: WRect, tolerance: Double = 1e-9) -> Bool {
        other.x >= x - tolerance && other.y >= y - tolerance && other.maxX <= maxX + tolerance && other.maxY <= maxY + tolerance
    }

    /// Whether the interiors of the two rectangles overlap by more than `tolerance` on both axes.
    public func overlaps(_ other: WRect, tolerance: Double = 1e-9) -> Bool {
        min(maxX, other.maxX) - max(x, other.x) > tolerance && min(maxY, other.maxY) - max(y, other.y) > tolerance
    }

    /// Linear interpolation towards `other`.
    public func lerp(to other: WRect, _ t: Double) -> WRect {
        WRect(x + (other.x - x) * t, y + (other.y - y) * t, w + (other.w - w) * t, h + (other.h - h) * t)
    }
}
