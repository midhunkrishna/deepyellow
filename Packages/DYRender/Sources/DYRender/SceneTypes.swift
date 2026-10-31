import DYCore
import Foundation
import simd

/// A double-precision camera over the world rectangle. `scale` 1 fits the whole world in the view.
public struct Camera: Equatable, Sendable {
    public var centerX: Double, centerY: Double, scale: Double
    public static let minScale = 0.85, maxScale = 4e9

    public init(centerX: Double, centerY: Double, scale: Double) {
        self.centerX = centerX; self.centerY = centerY; self.scale = scale
    }

    /// The camera that shows the whole world.
    public static func overview(world: WRect) -> Camera { Camera(centerX: world.x + world.w / 2, centerY: world.y + world.h / 2, scale: 1) }

    /// Pixels per world unit for a view `viewWidth` pixels wide.
    public func pixelsPerUnit(viewWidth: Double, world: WRect) -> Double { scale * viewWidth / world.w }

    /// The camera that frames `rect` inside the view with a fractional `margin` on each side.
    public static func fit(_ rect: WRect, viewPx: SIMD2<Double>, world: WRect, margin: Double = 0.04) -> Camera {
        let ppu = min(viewPx.x / max(rect.w, 1e-300), viewPx.y / max(rect.h, 1e-300)) * (1 - 2 * margin)
        let scale = min(max(ppu * world.w / viewPx.x, minScale), maxScale)
        return Camera(centerX: rect.x + rect.w / 2, centerY: rect.y + rect.h / 2, scale: scale)
    }

    /// Moves between two cameras so the world appears to slide and zoom at a constant rate, for `t` in 0...1.
    public static func blend(_ a: Camera, _ b: Camera, _ t: Double) -> Camera {
        let scale = exp(log(a.scale) + (log(b.scale) - log(a.scale)) * t)
        let denominator = 1 - a.scale / b.scale
        let f = abs(denominator) < 1e-6 ? t : (1 - a.scale / scale) / denominator
        return Camera(centerX: a.centerX + (b.centerX - a.centerX) * f, centerY: a.centerY + (b.centerY - a.centerY) * f, scale: scale)
    }
}

/// One rounded-rect instance as the tile shader reads it. Rectangles are in pixels, origin top-left.
///
/// - `params`: corner radius, type (0 tile, 1 directory plate, 2 dust), plate expansion or dust density, glow strength.
/// - `state`: decision (0 none, 1 keep, 2 remove, 3 later), selected, hovered, unused.
/// - `extra`: random seed, nesting depth, unused, unused.
public struct TileInstance {
    public var rect: SIMD4<Float>, color: SIMD4<Float>, params: SIMD4<Float>, state: SIMD4<Float>, extra: SIMD4<Float>
}

/// A request for text on the map, resolved into glyph quads by `LabelComposer`.
public struct LabelRequest {
    public enum Role { case tile, header, dust }
    public var role: Role
    public var node: NodeID
    /// The tile rectangle in pixels (x, y, width, height). For headers, the plate.
    public var rect: SIMD4<Float>
    public var alpha: Float
    public var darkText: Bool
    public var priority: Float
    /// Header band height in pixels. Zero for other roles.
    public var band: Float = 0
    public var dustFiles: UInt64 = 0, dustBytes: UInt64 = 0
}

/// Everything one frame needs: instances in painter's order, hit regions in the same order, and label requests.
public struct SceneOutput {
    public var tiles: [TileInstance] = []
    public var hitRects: [SIMD4<Float>] = []
    public var hitNodes: [NodeID] = []
    public var labels: [LabelRequest] = []
    /// The deepest directory that fills the view.
    public var focusNode: NodeID = 0
    /// World rectangles of every drawn node, filled only on request, to tween lens changes.
    public var worldRects: [NodeID: WRect] = [:]

    public init() {}

    /// The node under a pixel position, preferring the topmost tile.
    public func hit(x: Float, y: Float) -> NodeID? {
        var index = hitRects.count - 1
        while index >= 0 {
            let r = hitRects[index]
            if x >= r.x && x < r.z && y >= r.y && y < r.w { return hitNodes[index] }
            index -= 1
        }
        return nil
    }
}

/// Old rectangles to animate from after a lens change.
public struct TweenState {
    public var from: [NodeID: WRect]
    public var progress: Double
}
