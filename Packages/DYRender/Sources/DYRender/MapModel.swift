import DYCore
import Foundation
import QuartzCore
import simd

/// The map's state and behaviour with no AppKit or Metal: lens, layout, camera, animation and hit testing.
public final class MapModel {
    public private(set) var lens: TreeLens?
    public private(set) var style = NodeStyle()
    public private(set) var metric: Metric = .bytes
    public var selection: Set<NodeID> = []
    public var hover: NodeID = noNode
    public var reduceMotion = false
    public private(set) var layout: MapLayout?
    public private(set) var camera = Camera(centerX: 0.8, centerY: 0.5, scale: 1)
    public private(set) var focusNode: NodeID = 0
    public private(set) var lastScene = SceneOutput()
    private var dominant: [UInt8] = []
    private var approximateCache: (tree: ObjectIdentifier, kinds: [UInt8])?
    private var pendingFit = true
    private var cameraAnimation: (from: Camera, to: Camera, start: CFTimeInterval, duration: Double)?
    private var tween: (from: [NodeID: WRect], start: CFTimeInterval)?
    private static let tweenDuration = 0.32, cameraDuration = 0.28

    public init() {}

    /// Replaces what the map shows. A new lens or metric re-lays out, animating from the old rectangles if asked.
    public func setContent(lens newLens: TreeLens, style newStyle: NodeStyle, metric newMetric: Metric, selection newSelection: Set<NodeID>,
                           animated: Bool, viewPx: SIMD2<Double>, scale: Double, now: CFTimeInterval) {
        if newLens !== lens || newMetric != metric {
            var from: [NodeID: WRect] = [:]
            if animated, !reduceMotion, layout != nil {
                from = buildScene(viewPx: viewPx, scale: scale, now: now, recordWorldRects: true).worldRects
            }
            lens = newLens
            metric = newMetric
            layout = nil
            if focusNode >= newLens.tree.count { focusNode = 0 }
            tween = from.isEmpty ? nil : (from, now)
        }
        style = newStyle
        selection = newSelection
        if let tree = lens?.tree {
            if !newStyle.dominantKind.isEmpty { dominant = newStyle.dominantKind } else { dominant = approximateKinds(tree) }
        }
    }

    private func approximateKinds(_ tree: FileTree) -> [UInt8] {
        if let cache = approximateCache, cache.tree == ObjectIdentifier(tree) { return cache.kinds }
        let kinds = TileColoring.approximateDominantKinds(tree)
        approximateCache = (ObjectIdentifier(tree), kinds)
        return kinds
    }

    /// Creates or refreshes the layout for a view of `viewPx`, refitting the camera when the aspect or lens changed.
    @discardableResult
    public func ensureLayout(viewPx: SIMD2<Double>) -> MapLayout? {
        guard let lens, viewPx.x > 0, viewPx.y > 0 else { return nil }
        let aspect = viewPx.x / viewPx.y
        if let layout, abs(layout.worldRect.w - aspect) < 1e-3, !pendingFit { return layout }
        let rebuilt = (layout == nil || abs(layout!.worldRect.w - aspect) >= 1e-3)
        let first = layout == nil && lastScene.tiles.isEmpty
        if rebuilt { layout = MapLayout(lens: lens, metric: metric, worldAspect: aspect, dominantKind: dominant) }
        if first || pendingFit || (rebuilt && focusNode != 0) {
            camera = cameraFraming(focusNode, viewPx: viewPx)
            cameraAnimation = nil
        }
        pendingFit = false
        return layout
    }

    /// The camera that frames `node`, or the whole world when it has no rectangle.
    private func cameraFraming(_ node: NodeID, viewPx: SIMD2<Double>) -> Camera {
        guard let layout else { return Camera(centerX: 0.8, centerY: 0.5, scale: 1) }
        guard node != 0, let rect = layout.rect(of: node) else { return Camera.overview(world: layout.worldRect) }
        return Camera.fit(rect, viewPx: viewPx, world: layout.worldRect)
    }

    /// Moves the camera to frame `node`, with a short spring unless motion is reduced.
    public func focus(on node: NodeID, animated: Bool, viewPx: SIMD2<Double>, now: CFTimeInterval) {
        focusNode = node
        guard let layout, abs(layout.worldRect.w - viewPx.x / max(viewPx.y, 1)) < 1e-3 else { pendingFit = true; return }
        let target = cameraFraming(node, viewPx: viewPx)
        if animated, !reduceMotion { cameraAnimation = (camera, target, now, Self.cameraDuration) } else { camera = target; cameraAnimation = nil }
    }

    /// Builds the current frame's scene for a view of `viewPx` and updates the detected focus.
    @discardableResult
    public func buildScene(viewPx: SIMD2<Double>, scale: Double, now: CFTimeInterval, recordWorldRects: Bool = false) -> SceneOutput {
        guard let lens, let layout = ensureLayout(viewPx: viewPx) else { return SceneOutput() }
        var input = SceneInput(layout: layout, coloring: TileColoring(tree: lens.tree, style: style, dominantKind: dominant),
                               camera: camera, viewPx: viewPx, scale: scale)
        input.selection = selection
        input.hover = hover
        input.recordWorldRects = recordWorldRects
        if let tween {
            input.tween = TweenState(from: tween.from, progress: min((now - tween.start) / Self.tweenDuration, 1))
        }
        let scene = MapSceneBuilder(input).build()
        if !recordWorldRects { lastScene = scene }
        return scene
    }

    /// Advances animations to `now`. Returns true while anything is still moving.
    public func step(now: CFTimeInterval) -> Bool {
        var active = false
        if let anim = cameraAnimation {
            let t = min((now - anim.start) / anim.duration, 1)
            camera = Camera.blend(anim.from, anim.to, Self.spring(t))
            if t >= 1 { camera = anim.to; cameraAnimation = nil } else { active = true }
        }
        if let tween {
            if now - tween.start >= Self.tweenDuration { self.tween = nil } else { active = true }
        }
        return active
    }

    /// An ease-out with a slight overshoot, which reads as a spring settling.
    private static func spring(_ t: Double) -> Double {
        let c1 = 0.55, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    /// Zooms by `factor` keeping the world point under `anchorPx` fixed.
    public func zoom(by factor: Double, anchorPx: SIMD2<Double>, viewPx: SIMD2<Double>) {
        guard let layout else { return }
        cameraAnimation = nil
        let before = camera.pixelsPerUnit(viewWidth: viewPx.x, world: layout.worldRect)
        let scale = min(max(camera.scale * factor, Camera.minScale), Camera.maxScale)
        let after = before * scale / camera.scale
        let worldX = camera.centerX + (anchorPx.x - viewPx.x / 2) / before
        let worldY = camera.centerY + (anchorPx.y - viewPx.y / 2) / before
        camera.scale = scale
        camera.centerX = worldX - (anchorPx.x - viewPx.x / 2) / after
        camera.centerY = worldY - (anchorPx.y - viewPx.y / 2) / after
        clampCenter()
    }

    /// Drags the world by a pixel delta.
    public func pan(byPx delta: SIMD2<Double>, viewPx: SIMD2<Double>) {
        guard let layout else { return }
        cameraAnimation = nil
        let ppu = camera.pixelsPerUnit(viewWidth: viewPx.x, world: layout.worldRect)
        camera.centerX -= delta.x / ppu
        camera.centerY -= delta.y / ppu
        clampCenter()
    }

    /// Keeps the camera centre inside the world.
    private func clampCenter() {
        guard let world = layout?.worldRect else { return }
        camera.centerX = min(max(camera.centerX, world.x), world.maxX)
        camera.centerY = min(max(camera.centerY, world.y), world.maxY)
    }

    /// The node under a pixel position in the last scene.
    public func hitTest(px: SIMD2<Double>) -> NodeID? { lastScene.hit(x: Float(px.x), y: Float(px.y)) }
}
