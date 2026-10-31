import AppKit
import DYCore
import Metal
import QuartzCore
import simd

/// One arc as the ring shader reads it. Must match `ArcInstance` in the shader source.
struct ArcInstance {
    var geom: SIMD4<Float>, angles: SIMD4<Float>, color: SIMD4<Float>, state: SIMD4<Float>, extra: SIMD4<Float>, bbox: SIMD4<Float>
}

/// A sunburst of the focused directory: five rings of arcs, dust arcs for slivers, name and size in the hole.
public final class RingsCanvas: MetalCanvasView, DiskCanvas {
    public var events = CanvasEvents()
    private var lens: TreeLens?
    private var style = NodeStyle()
    private var metric: Metric = .bytes
    private var selection: Set<NodeID> = []
    private var root: NodeID = 0
    private var arcs: [RingArc] = []
    private var byDepth: [[Int]] = []
    private var hover: NodeID = noNode
    private var appearStart: CFTimeInterval = -10
    private var reportedFocus: NodeID = noNode
    private var pipeline: MTLRenderPipelineState?
    private var ring: BufferRing?
    private var tiles: TileRenderer?
    private var labels: LabelRenderer?
    private var trackingArea: NSTrackingArea?
    private var lastGeometry = RingsGeometry(viewPx: SIMD2(800, 800), margin: 20)
    private static let appearDuration = 0.3
    /// Number of arcs drawn in the last frame, for tests and benchmarks.
    public private(set) var lastArcCount = 0

    public override init(frame: NSRect) { super.init(frame: frame); setUp() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setUp() }

    private func setUp() {
        guard let gpu else { return }
        if let library = try? gpu.library(named: "rings", source: Shaders.rings) {
            pipeline = try? gpu.blendedPipeline(library: library, vertex: "ringVertex", fragment: "ringFragment")
        }
        ring = BufferRing(device: gpu.device)
        tiles = try? TileRenderer(gpu: gpu)
        labels = try? LabelRenderer(gpu: gpu)
    }

    // MARK: DiskCanvas

    public func update(lens newLens: TreeLens, style newStyle: NodeStyle, metric newMetric: Metric, selection newSelection: Set<NodeID>, animated: Bool) {
        let relayout = newLens !== lens || newMetric != metric
        lens = newLens; style = newStyle; metric = newMetric; selection = newSelection
        if relayout {
            if root >= newLens.tree.count { root = 0 }
            rebuildArcs()
            beginAppear(animated: animated)
        }
        setNeedsRender()
    }

    public func focus(on node: NodeID, animated: Bool) {
        guard let lens, node >= 0, Int(node) < lens.tree.count else { return }
        root = node
        rebuildArcs()
        beginAppear(animated: animated)
        setNeedsRender()
    }

    public func snapshot(size: CGSize, scale: CGFloat) -> CGImage? { renderOffscreen(size: size, scale: scale).image }

    private func beginAppear(animated: Bool) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { appearStart = -10; return }
        appearStart = CACurrentMediaTime()
        startAnimating()
    }

    /// Recomputes the arcs for the current root and notes the new focus.
    private func rebuildArcs() {
        guard let lens else { return }
        arcs = RingsLayout.arcs(lens: lens, metric: metric, root: root)
        byDepth = Array(repeating: [], count: RingsLayout.levels)
        for (index, arc) in arcs.enumerated() { byDepth[arc.depth].append(index) }
        if root != reportedFocus {
            reportedFocus = root
            let node = root
            DispatchQueue.main.async { [weak self] in self?.events.onFocusChanged?(node) }
        }
    }

    public override func step(now: CFTimeInterval) -> Bool { now - appearStart < Self.appearDuration }

    // MARK: Drawing

    /// The fade-in progress for a frame at `time`.
    private func appearance(_ time: CFTimeInterval) -> Float {
        let t = min(max((time - appearStart) / Self.appearDuration, 0), 1)
        return Float(1 - pow(1 - t, 3))
    }

    public override func encode(_ target: RenderTarget, encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {
        guard let lens, let pipeline, let ring, let tiles, let labels else { return }
        let viewPx = SIMD2(Double(target.viewPx.x), Double(target.viewPx.y))
        let geometry = RingsGeometry(viewPx: viewPx, margin: 22 * Double(target.scale))
        lastGeometry = geometry
        let fade = appearance(target.time)
        let coloring = TileColoring(tree: lens.tree, style: style, dominantKind: style.dominantKind.isEmpty ? TileColoring.approximateDominantKinds(lens.tree) : style.dominantKind)
        var instances: [ArcInstance] = []
        for arc in arcs { instances.append(instance(arc, geometry, coloring, scale: target.scale, fade: fade)) }
        lastArcCount = instances.count
        if !instances.isEmpty, let buffer = instances.withUnsafeBufferPointer({ ring.upload($0.baseAddress!, count: $0.count) }) {
            var uniforms = TileUniforms(viewSize: target.viewPx, gap: target.scale, scale: target.scale, background: SIMD4(Palette.background, 1),
                                        surface: SIMD4(Palette.surface, 1), accent: SIMD4(Palette.accent, 1), removeColor: SIMD4(Palette.remove, 1),
                                        keepColor: SIMD4(Palette.keep, 1), laterColor: SIMD4(Palette.later, 1), text: SIMD4(Palette.textPrimary, 1))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 1)
            encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
        }
        _ = tiles
        labels.atlas.beginFrame()
        let quads = ringLabels(lens, geometry, coloring, scale: target.scale, fade: fade, composer: labels.composer)
        labels.encode(quads, viewPx: target.viewPx, encoder: encoder)
    }

    /// Builds the GPU instance for one arc.
    private func instance(_ arc: RingArc, _ g: RingsGeometry, _ coloring: TileColoring, scale: Float, fade: Float) -> ArcInstance {
        let r0 = g.edges[arc.depth], r1 = g.edges[arc.depth + 1]
        let owner = arc.isDust ? arc.parent : arc.node
        var color = arc.isDust ? dustColor(arc, coloring) : coloring.color(of: arc.node)
        // Directories that open into further rings are muted like the map's plates; files and outer arcs keep full colour.
        if !arc.isDust, arc.isDirectory, arc.depth < RingsLayout.levels - 1 { color = simd_mix(Palette.surfaceRaised, color, SIMD3(repeating: 0.5)) }
        let glow = arc.isDust ? coloring.glow(of: arc.parent) * 0.4 : coloring.glow(of: arc.node)
        let decision = arc.isDust ? Decision.none : coloring.decision(of: arc.node)
        let parentDecision = arc.parent == arc.node ? Decision.none : coloring.decision(of: arc.parent)
        let pad = Double(3 + glow * 14 * scale)
        let box = bounds(of: arc, g, r0: r0 - pad, r1: r1 + pad)
        let density = Float(min(max(pow(Double(arc.dustFiles) / max(arc.span * (r0 + r1) * 0.5 * (r1 - r0) / pow(2.6 * Double(scale), 2), 1), 0.55) * 1.3, 0.08), 1))
        let seed = Float((UInt32(bitPattern: owner) &* 2_654_435_761 &+ UInt32(arc.depth)) & 0xFFFF)
        let corner = Float(min(3.2 * Double(scale), (r1 - r0) * 0.22))
        return ArcInstance(geom: SIMD4(Float(g.centre.x), Float(g.centre.y), Float(r0), Float(r1)),
                           angles: SIMD4(Float(arc.start), Float(arc.end), corner, arc.isDust ? 2 : 0),
                           color: SIMD4(color, fade),
                           state: SIMD4(Float(decision.rawValue), selection.contains(arc.node) && !arc.isDust ? 1 : 0,
                                        hover == owner && !arc.isDust ? 1 : 0, decision != parentDecision ? 1 : 0),
                           extra: SIMD4(seed, Float(arc.depth), glow, density), bbox: box)
    }

    /// The colour of a dust arc: the dominant kind in kind mode, otherwise the parent's colour.
    private func dustColor(_ arc: RingArc, _ coloring: TileColoring) -> SIMD3<Float> {
        coloring.color(of: arc.parent)
    }

    /// A tight pixel rectangle around an annular sector (x, y, width, height).
    private func bounds(of arc: RingArc, _ g: RingsGeometry, r0: Double, r1: Double) -> SIMD4<Float> {
        var xs: [Double] = [], ys: [Double] = []
        var angles = [arc.start, arc.end]
        var quarter = (arc.start / (Double.pi / 2)).rounded(.up) * (Double.pi / 2)
        while quarter < arc.end { angles.append(quarter); quarter += Double.pi / 2 }
        for angle in angles { for radius in [max(r0, 0), r1] { xs.append(g.centre.x + cos(angle) * radius); ys.append(g.centre.y + sin(angle) * radius) } }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        return SIMD4(Float(minX), Float(minY), Float(maxX - minX), Float(maxY - minY))
    }

    /// Text for the hole and for arcs that have room, rotated along their radius.
    private func ringLabels(_ lens: TreeLens, _ g: RingsGeometry, _ coloring: TileColoring, scale: Float, fade: Float, composer: LabelComposer) -> [LabelQuad] {
        var quads: [LabelQuad] = []
        let cx = Float(g.centre.x), cy = Float(g.centre.y)
        let holeWidth = Float(g.hole * 2) - 24 * scale
        let rootName = root == 0 ? (lens.tree.name(0) == "/" ? "Macintosh HD" : lens.tree.name(0)) : lens.tree.name(root)
        let nameSize = min(max(Float(g.hole) * 0.17, 12 * scale), 24 * scale).rounded()
        if let name = composer.caption(TextSpec(text: rootName, size: nameSize, weight: .semibold), x: cx, y: cy - nameSize * 1.5, available: holeWidth,
                                       color: SIMD4(Palette.textPrimary, fade), align: .center) {
            quads.append(name.quad)
        }
        let primary = metric == .bytes ? Format.bytes(lens.size[Int(root)]) : "\(Format.count(lens.files[Int(root)])) files"
        let secondary = metric == .bytes ? "\(Format.count(lens.files[Int(root)])) files" : Format.bytes(lens.size[Int(root)])
        if let size = composer.caption(TextSpec(text: primary, size: (nameSize * 1.25).rounded(), weight: .regular, tabular: true), x: cx, y: cy - nameSize * 0.1,
                                       available: holeWidth, color: SIMD4(Palette.textSecondary, fade), align: .center) { quads.append(size.quad) }
        if let files = composer.caption(TextSpec(text: secondary, size: (nameSize * 0.8).rounded(), tabular: true), x: cx, y: cy + nameSize * 1.6,
                                        available: holeWidth, color: SIMD4(Palette.textMuted, fade), align: .center) { quads.append(files.quad) }
        for arc in arcs where !arc.isDust {
            if quads.count > 280 { break }
            quads.append(contentsOf: arcLabel(arc, lens, g, coloring, scale: scale, fade: fade, composer: composer))
        }
        return quads
    }

    /// A radial name (and size, when there is room) for one arc, readable from either side of the circle.
    private func arcLabel(_ arc: RingArc, _ lens: TreeLens, _ g: RingsGeometry, _ coloring: TileColoring, scale: Float, fade: Float, composer: LabelComposer) -> [LabelQuad] {
        let r0 = g.edges[arc.depth], r1 = g.edges[arc.depth + 1]
        let thickness = arc.span * (r0 + r1) / 2
        let size = (arc.depth == 0 ? 13 : 11) * scale
        let lineHeight = Double(size) * 1.3
        let pad = 8 * Double(scale)
        let length = r1 - r0 - 2 * pad
        guard thickness >= lineHeight * 1.15, length >= Double(size) * 3.5 else { return [] }
        let mid = (arc.start + arc.end) / 2
        let direction = SIMD2(cos(mid), sin(mid))
        let flipped = cos(mid) < 0
        let anchorRadius = flipped ? r1 - pad : r0 + pad
        let anchor = g.centre + direction * anchorRadius
        let angle = Float(flipped ? mid + Double.pi : mid)
        let dark = TileColoring.prefersDarkText(coloring.color(of: arc.node))
        let ink: SIMD3<Float> = dark ? SIMD3(0.08, 0.06, 0.03) : Palette.textPrimary
        let twoLines = thickness >= lineHeight * 2.3
        var quads: [LabelQuad] = []
        let nameY = twoLines ? Float(anchor.y) - Float(lineHeight) * 0.95 : Float(anchor.y) - Float(lineHeight) / 2
        let pivot = SIMD4(Float(anchor.x), Float(anchor.y), angle, 0)
        if var name = composer.caption(TextSpec(text: lens.tree.name(arc.node), size: size, weight: .medium), x: Float(anchor.x), y: nameY,
                                       available: Float(length), color: SIMD4(ink, fade * 0.96)) {
            name.quad.rotation = pivot
            quads.append(name.quad)
        }
        if twoLines {
            let text = metric == .bytes ? Format.bytes(lens.size[Int(arc.node)]) : "\(Format.count(lens.files[Int(arc.node)])) files"
            if var detail = composer.caption(TextSpec(text: text, size: (size * 0.9).rounded(), tabular: true), x: Float(anchor.x), y: Float(anchor.y) + Float(lineHeight) * 0.05,
                                             available: Float(length), color: SIMD4(ink, fade * 0.7)) {
                detail.quad.rotation = pivot
                quads.append(detail.quad)
            }
        }
        return quads
    }

    // MARK: Input

    /// The arc under a pixel position, or nil when over the hole or outside the rings.
    func arc(atPx point: SIMD2<Double>) -> RingArc? {
        guard let spot = lastGeometry.locate(point), spot.depth < byDepth.count else { return nil }
        let angle = spot.angle + RingsLayout.topAngle
        for index in byDepth[spot.depth] where arcs[index].start <= angle && angle < arcs[index].end { return arcs[index] }
        return nil
    }

    private func pixelPoint(_ event: NSEvent) -> SIMD2<Double> {
        let p = convert(event.locationInWindow, from: nil)
        return SIMD2(Double(p.x * backingScale), Double(p.y * backingScale))
    }

    private func overHole(_ point: SIMD2<Double>) -> Bool {
        let d = point - lastGeometry.centre
        return (d.x * d.x + d.y * d.y).squareRoot() < lastGeometry.hole
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        let hit = arc(atPx: pixelPoint(event))
        let node = hit.map { $0.isDust ? $0.parent : $0.node } ?? noNode
        guard node != hover else { return }
        hover = node
        setNeedsRender()
        events.onHover?(node == noNode ? nil : node, convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        guard hover != noNode else { return }
        hover = noNode
        setNeedsRender()
        events.onHover?(nil, .zero)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = pixelPoint(event)
        if event.clickCount >= 2 {
            if overHole(point), let lens, root != 0 {
                let parent = lens.tree.parent(root)
                events.onDoubleClick?(root)
                focus(on: parent, animated: true)
            } else if let hit = arc(atPx: point) {
                let node = hit.isDust ? hit.parent : hit.node
                events.onDoubleClick?(node)
                focus(on: hit.isDirectory || hit.isDust ? node : hit.parent, animated: true)
            }
        } else if let hit = arc(atPx: point) {
            events.onClick?(hit.isDust ? hit.parent : hit.node, event.modifierFlags)
        } else if overHole(point) {
            events.onClick?(root, event.modifierFlags)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let hit = arc(atPx: pixelPoint(event)) { events.onContextMenu?(hit.isDust ? hit.parent : hit.node, event) }
    }
}
