import DYCore
import Foundation
import simd

/// Inputs for one frame of the map.
public struct SceneInput {
    public var layout: MapLayout
    public var coloring: TileColoring
    public var camera: Camera
    public var viewPx: SIMD2<Double>
    /// Backing scale: pixels per point. Size thresholds are written in points.
    public var scale: Double
    public var selection: Set<NodeID> = []
    public var hover: NodeID = noNode
    public var tween: TweenState?
    public var recordWorldRects = false
}

/// Walks the lazy layout for the current camera and emits only what is visible and large enough to matter.
///
/// Cost is bounded by the screen: tiles under a pixel are skipped, a directory expands smoothly as it grows past a
/// size, and dust expands into its next chunk when its largest piece becomes visible.
public final class MapSceneBuilder {
    private let input: SceneInput
    private let layout: MapLayout
    private let tree: FileTree
    private let lens: TreeLens
    private let coloring: TileColoring
    private let ppu: Double
    private let pt: Double
    private let viewW: Double, viewH: Double
    private var out = SceneOutput()
    /// How many partially resolved dust tiles enclose the current position. Only the outermost draws, so chains don't stack.
    private var dustDepth = 0

    /// Creates a builder for one frame.
    public init(_ input: SceneInput) {
        self.input = input
        layout = input.layout
        lens = input.layout.lens
        tree = input.layout.lens.tree
        coloring = input.coloring
        viewW = input.viewPx.x
        viewH = input.viewPx.y
        pt = input.scale
        ppu = input.camera.pixelsPerUnit(viewWidth: input.viewPx.x, world: input.layout.worldRect)
    }

    /// Builds the scene.
    public func build() -> SceneOutput {
        out.tiles.reserveCapacity(4096)
        visit(0, world: layout.worldRect, depth: 0, fade: 1)
        return out
    }

    /// Converts a world rectangle to pixels, relative to the camera so precision survives deep zoom.
    private func screen(_ r: WRect) -> (x: Double, y: Double, w: Double, h: Double) {
        ((r.x - input.camera.centerX) * ppu + viewW / 2, (r.y - input.camera.centerY) * ppu + viewH / 2, r.w * ppu, r.h * ppu)
    }

    private func isOffscreen(_ s: (x: Double, y: Double, w: Double, h: Double)) -> Bool {
        s.x > viewW + 1 || s.y > viewH + 1 || s.x + s.w < -1 || s.y + s.h < -1
    }

    /// The rectangle to draw `node` at, interpolated from its previous place while a lens change animates.
    private func tweened(_ node: NodeID, _ world: WRect) -> (WRect, Float) {
        guard let tween = input.tween, tween.progress < 1 else { return (world, 1) }
        let eased = 1 - pow(1 - tween.progress, 3)
        if let old = tween.from[node] { return (old.lerp(to: world, eased), 1) }
        return (world, Float(eased))
    }

    private func smoothstep(_ x: Double, _ lo: Double, _ hi: Double) -> Float {
        let t = min(max((x - lo) / (hi - lo), 0), 1)
        return Float(t * t * (3 - 2 * t))
    }

    /// Emits a node, and its children when it is a directory large enough on screen.
    private func visit(_ node: NodeID, world: WRect, depth: Int, fade parentFade: Float, parentDecision: Decision = .none) {
        let (rect, nodeFade) = tweened(node, world)
        let s = screen(rect)
        guard !isOffscreen(s), s.w >= 0.7, s.h >= 0.7 else { return }
        let fade = parentFade * nodeFade
        guard fade > 0.004 else { return }
        if input.recordWorldRects { out.worldRects[node] = world }

        var expand: Float = 0
        if tree.columns.childCount[Int(node)] > 0 {
            expand = smoothstep(min(s.w, s.h) / pt, 26, 54)
            if expand > 0, layout.children(of: node).count == 0 { expand = 0 }
        }
        let color = coloring.color(of: node)
        let decision = coloring.decision(of: node)
        let isPlate = expand > 0
        emit(node: node, hitNode: node, s: s, color: color, alpha: fade, type: isPlate ? 1 : 0, aux: expand,
             glow: coloring.glow(of: node) * (isPlate ? 0.5 : 1), depth: depth, decision: decision, glyph: decision != parentDecision, inset: isPlate ? plateInset(world, slim: layout.isChain(node)) : .zero)
        if isPlate {
            noteFocus(node, s)
            let slim = layout.isChain(node)
            addHeaderLabel(node, rect, s, alpha: fade * max(0, (expand - 0.3) / 0.7), slim: slim)
            addTileLabel(node, s, color, alpha: fade * max(0, 1 - expand * 3))
            let outerDust = dustDepth
            dustDepth = 0
            visitContainer(parent: node, start: 0, rect: layout.contentRect(of: world, slim: slim), depth: depth + 1, fade: fade * expand, parentDecision: decision)
            dustDepth = outerDust
        } else {
            addTileLabel(node, s, color, alpha: fade)
        }
    }

    /// Visits the chunk of children laid out inside `rect`, then the dust tile that stands for the rest.
    private func visitContainer(parent: NodeID, start: Int, rect: WRect, depth: Int, fade: Float, parentDecision: Decision = .none) {
        guard !isOffscreen(screen(rect)) else { return }
        for tile in layout.layout(parent: parent, start: start, in: rect).tiles {
            if let tail = tile.tail {
                visitDust(tile, tail, parent: parent, depth: depth, fade: fade, parentDecision: parentDecision)
            } else {
                visit(tile.node, world: tile.rect, depth: depth, fade: fade, parentDecision: parentDecision)
            }
        }
    }

    /// Emits a dust tile, and resolves it into the next chunk once its largest piece is big enough to see.
    private func visitDust(_ tile: LayoutTile, _ tail: TailInfo, parent: NodeID, depth: Int, fade: Float, parentDecision: Decision) {
        let s = screen(tile.rect)
        guard !isOffscreen(s), s.w >= 1.2, s.h >= 1.2 else { return }
        let areaPx = s.w * s.h
        let share = Double(tail.firstValue) / max(Double(tile.value), 1)
        let resolve = smoothstep(sqrt(areaPx * share) / pt, 4.5, 12)
        let cells = areaPx / pow(2.6 * pt, 2)
        let density = Float(min(max(pow(Double(tail.files) / max(cells, 1), 0.55) * 1.3, 0.08), 1))
        let color = coloring.style.colorMode == .kind ? Palette.kind(FileKind(rawValue: tail.kind) ?? .other) : coloring.color(of: parent)
        if fade * (1 - resolve) > 0.01, resolve < 0.02 || (dustDepth == 0 && resolve < 0.995) {
        emit(node: parent, hitNode: parent, s: s, color: color, alpha: fade * (1 - resolve), type: 2, aux: density,
             glow: coloring.glow(of: parent) * 0.4, depth: depth, decision: .none, glyph: false)
        }
        if s.w >= 90 * pt, s.h >= 30 * pt, resolve < 0.25 {
            out.labels.append(LabelRequest(role: .dust, node: parent, rect: SIMD4(Float(s.x), Float(s.y), Float(s.w), Float(s.h)),
                                           alpha: fade * (1 - resolve * 4), darkText: false, priority: Float(areaPx),
                                           dustFiles: tail.files, dustBytes: tail.bytes))
        }
        if resolve > 0.01, fade * resolve > 0.01 {
            dustDepth += 1
            visitContainer(parent: parent, start: tail.start, rect: tile.rect, depth: depth, fade: fade * resolve, parentDecision: parentDecision)
            dustDepth -= 1
        }
    }

    /// Appends one instance and its hit region.
    private func emit(node: NodeID, hitNode: NodeID, s: (x: Double, y: Double, w: Double, h: Double), color: SIMD3<Float>,
                      alpha: Float, type: Float, aux: Float, glow: Float, depth: Int, decision: Decision, glyph: Bool, inset: SIMD2<Float> = .zero) {
        let limit = 20_000.0
        let x0 = max(s.x, -limit), y0 = max(s.y, -limit)
        let x1 = min(s.x + s.w, viewW + limit), y1 = min(s.y + s.h, viewH + limit)
        let radius = Float(min(3.2 * pt, min(x1 - x0, y1 - y0) * 0.22))
        let selected: Float = input.selection.contains(node) && type != 2 ? 1 : 0
        let hovered: Float = input.hover == node && type != 2 ? 1 : 0
        let seed = Float((UInt32(bitPattern: node) &* 2_654_435_761 &+ UInt32(depth)) & 0xFFFF)
        out.tiles.append(TileInstance(rect: SIMD4(Float(x0), Float(y0), Float(x1 - x0), Float(y1 - y0)),
                                      color: SIMD4(color, alpha), params: SIMD4(radius, type, aux, glow),
                                      state: SIMD4(Float(decision.rawValue), selected, hovered, glyph ? 1 : 0), extra: SIMD4(seed, Float(depth), inset.x, inset.y)))
        out.hitRects.append(SIMD4(Float(max(s.x, 0)), Float(max(s.y, 0)), Float(min(s.x + s.w, viewW)), Float(min(s.y + s.h, viewH))))
        out.hitNodes.append(hitNode)
    }

    /// Padding and top inset in pixels between a plate's edge and its children, so the shader can skip covered pixels.
    private func plateInset(_ world: WRect, slim: Bool) -> SIMD2<Float> {
        let content = layout.contentRect(of: world, slim: slim)
        return SIMD2(Float((content.x - world.x) * ppu), Float((content.y - world.y) * ppu))
    }

    /// Records a directory as the focus when it fills the middle of the view.
    private func noteFocus(_ node: NodeID, _ s: (x: Double, y: Double, w: Double, h: Double)) {
        if s.x <= viewW * 0.2, s.y <= viewH * 0.2, s.x + s.w >= viewW * 0.8, s.y + s.h >= viewH * 0.8 { out.focusNode = node }
    }

    /// Adds a name and size label to a tile that is large enough to carry one.
    private func addTileLabel(_ node: NodeID, _ s: (x: Double, y: Double, w: Double, h: Double), _ color: SIMD3<Float>, alpha: Float) {
        guard alpha > 0.02, s.w >= 56 * pt, s.h >= 26 * pt else { return }
        out.labels.append(LabelRequest(role: .tile, node: node, rect: SIMD4(Float(s.x), Float(s.y), Float(s.w), Float(s.h)), alpha: alpha,
                                       darkText: TileColoring.prefersDarkText(color), priority: Float(s.w * s.h)))
    }

    /// Adds a directory header label when the band is tall enough to read.
    private func addHeaderLabel(_ node: NodeID, _ rect: WRect, _ s: (x: Double, y: Double, w: Double, h: Double), alpha: Float, slim: Bool) {
        let band = layout.headerHeight(of: rect, slim: slim) * ppu
        guard alpha > 0.02, band >= 11 * pt, s.w >= 60 * pt else { return }
        out.labels.append(LabelRequest(role: .header, node: node, rect: SIMD4(Float(s.x), Float(s.y), Float(s.w), Float(s.h)), alpha: alpha,
                                       darkText: false, priority: Float.greatestFiniteMagnitude / 2 + Float(band), band: Float(band)))
    }
}
