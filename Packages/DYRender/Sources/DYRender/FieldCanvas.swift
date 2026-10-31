import AppKit
import DYCore
import Metal
import QuartzCore
import simd

/// Uniforms for the star and tone-mapping passes. Must match `FieldUniforms` in the shader source.
struct FieldUniforms {
    var viewSize: SIMD2<Float>, plotOrigin: SIMD2<Float>, plotSize: SIMD2<Float>, xRange: SIMD2<Float>, yRange: SIMD2<Float>
    var scale: Float, exposure: Float
    var pad: SIMD2<Float> = .zero
    var background: SIMD4<Float>, accent: SIMD4<Float>
}

/// Every file as a point of light: age on x, size on y, both logarithmic. Additive blending and tone mapping make swarms glow.
public final class FieldCanvas: MetalCanvasView, DiskCanvas {
    public var events = CanvasEvents()
    private var count = 0
    private var nodes: [NodeID] = []
    private var kinds: [UInt8] = []
    private var xRange: ClosedRange<Float> = 0...3
    private var yRange: ClosedRange<Float> = 3...10
    private var positionBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var positions: [SIMD2<Float>] = []
    private var candidates: [Int32] = []
    private var lens: TreeLens?
    private var style = NodeStyle()
    private var selection: Set<NodeID> = []
    private var hdr: MTLTexture?
    private var starPipeline: MTLRenderPipelineState?
    private var tonePipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var tiles: TileRenderer?
    private var labels: LabelRenderer?
    private var brushStart: SIMD2<Double>?
    private var brush: (SIMD2<Double>, SIMD2<Double>)?
    private var hover: NodeID = noNode
    private var trackingArea: NSTrackingArea?
    /// Exposure of the tone mapper. Higher shows faint swarms more strongly.
    public var exposure: Float = 1.6 { didSet { starsDirty = true } }
    /// True when the star pass must be redrawn; false lets brush drags and hover reuse the cached half-float image.
    private var starsDirty = true
    private static let candidateLimit = 20_000

    /// How strongly to lift small points: 1 for a few hundred points or fewer, fading smoothly to exactly 0 at 20,000.
    /// Dense fields therefore render exactly as before.
    static func fewPointBoost(count: Int) -> Float {
        let t = min(max((log10(Float(max(count, 1))) - 2.5) / (log10(20_000) - 2.5), 0), 1)
        return count >= 20_000 ? 0 : 1 - t * t * (3 - 2 * t)
    }

    /// Forces the next frame to redraw every star, as after a resize. Used by benchmarks.
    public func invalidateStars() { starsDirty = true }

    public override init(frame: NSRect) { super.init(frame: frame); setUp() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setUp() }

    private func setUp() {
        guard let gpu, let library = try? gpu.library(named: "field", source: Shaders.field) else { return }
        let star = MTLRenderPipelineDescriptor()
        star.vertexFunction = library.makeFunction(name: "starVertex")
        star.fragmentFunction = library.makeFunction(name: "starFragment")
        let attachment = star.colorAttachments[0]!
        attachment.pixelFormat = .rgba16Float
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one; attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one; attachment.destinationAlphaBlendFactor = .one
        starPipeline = try? gpu.device.makeRenderPipelineState(descriptor: star)
        let tone = MTLRenderPipelineDescriptor()
        tone.vertexFunction = library.makeFunction(name: "toneVertex")
        tone.fragmentFunction = library.makeFunction(name: "toneFragment")
        tone.colorAttachments[0].pixelFormat = .bgra8Unorm
        tonePipeline = try? gpu.device.makeRenderPipelineState(descriptor: tone)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear; samplerDescriptor.magFilter = .linear; samplerDescriptor.mipFilter = .linear
        sampler = gpu.device.makeSamplerState(descriptor: samplerDescriptor)
        tiles = try? TileRenderer(gpu: gpu)
        labels = try? LabelRenderer(gpu: gpu)
    }

    // MARK: Data

    /// Replaces the points. `positions` are (log10 age in days, log10 bytes); `kinds` and `nodes` are parallel arrays.
    public func setPoints(positions: [SIMD2<Float>], kinds: [UInt8], nodes: [NodeID], ageRange: ClosedRange<Float>, sizeRange: ClosedRange<Float>) {
        guard let gpu, positions.count == kinds.count, positions.count == nodes.count else { return }
        count = positions.count
        self.nodes = nodes
        self.kinds = kinds
        self.positions = positions
        let padX = max((ageRange.upperBound - ageRange.lowerBound) * 0.04, 0.05), padY = max((sizeRange.upperBound - sizeRange.lowerBound) * 0.04, 0.05)
        xRange = (ageRange.lowerBound - padX)...(ageRange.upperBound + padX)
        yRange = (sizeRange.lowerBound - padY)...(sizeRange.upperBound + padY)
        positionBuffer = positions.withUnsafeBytes { gpu.device.makeBuffer(bytes: $0.baseAddress!, length: max($0.count, 16), options: .storageModeShared) }
        colorBuffer = gpu.device.makeBuffer(length: max(count * 4, 16), options: .storageModeShared)
        starsDirty = true
        buildCandidates()
        rebuildColors()
        brush = nil
        setNeedsRender()
    }

    /// Picks the biggest points as the only ones that can be hovered or clicked.
    private func buildCandidates() {
        guard count > 0 else { candidates = []; return }
        let stride = max(1, count / 4000)
        let sample = Swift.stride(from: 0, to: count, by: stride).map { positions[$0].y }.sorted()
        let wanted = Double(Self.candidateLimit) / Double(count)
        let threshold = sample[min(sample.count - 1, Int(Double(sample.count) * max(0, 1 - wanted)))]
        var picked: [Int32] = []
        for index in 0..<count where positions[index].y >= threshold { picked.append(Int32(index)); if picked.count >= Self.candidateLimit * 2 { break } }
        candidates = picked
    }

    /// Writes one RGBA8 colour per point: hue from the active colour mode, brightness lifted so dim hues still shine as lights.
    private func rebuildColors() {
        guard let buffer = colorBuffer, count > 0 else { return }
        starsDirty = true
        let out = buffer.contents().bindMemory(to: UInt8.self, capacity: count * 4)
        let coloring = lens.map { TileColoring(tree: $0.tree, style: style, dominantKind: []) }
        let kindColors = FileKind.allCases.map { Palette.kind($0) }
        let useKinds = style.colorMode == .kind || coloring == nil
        let selected = selection
        let chunks = 16, per = (count + chunks - 1) / chunks
        DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            for index in min(chunk * per, count)..<min(count, (chunk + 1) * per) {
                var color = useKinds ? kindColors[Int(min(kinds[index], 7))] : coloring!.color(of: nodes[index])
                let peak = max(color.x, color.y, color.z, 0.05)
                color *= pow(1 / peak, 0.6)
                out[index * 4] = UInt8(min(color.x, 1) * 255); out[index * 4 + 1] = UInt8(min(color.y, 1) * 255)
                out[index * 4 + 2] = UInt8(min(color.z, 1) * 255)
                out[index * 4 + 3] = selected.contains(nodes[index]) ? 255 : 0
            }
        }
    }

    // MARK: DiskCanvas

    public func update(lens newLens: TreeLens, style newStyle: NodeStyle, metric: Metric, selection newSelection: Set<NodeID>, animated: Bool) {
        lens = newLens; style = newStyle; selection = newSelection
        rebuildColors()
        setNeedsRender()
    }

    public func focus(on node: NodeID, animated: Bool) {}

    public func snapshot(size: CGSize, scale: CGFloat) -> CGImage? { renderOffscreen(size: size, scale: scale).image }

    // MARK: Drawing

    /// The plot rectangle in pixels: x, y, width, height.
    private func plot(_ viewPx: SIMD2<Float>, _ scale: Float) -> SIMD4<Float> {
        let left = 78 * scale, top = 34 * scale, right = 30 * scale, bottom = 58 * scale
        return SIMD4(left, top, viewPx.x - left - right, viewPx.y - top - bottom)
    }

    private func uniforms(_ target: RenderTarget) -> FieldUniforms {
        let p = plot(target.viewPx, target.scale)
        return FieldUniforms(viewSize: target.viewPx, plotOrigin: SIMD2(p.x, p.y), plotSize: SIMD2(p.z, p.w),
                             xRange: SIMD2(xRange.lowerBound, xRange.upperBound), yRange: SIMD2(yRange.lowerBound, yRange.upperBound),
                             scale: target.scale, exposure: exposure, pad: SIMD2(Self.fewPointBoost(count: count), 0), background: SIMD4(Palette.background, 1), accent: SIMD4(Palette.accent, 1))
    }

    public override func prepare(_ target: RenderTarget, commandBuffer: MTLCommandBuffer) {
        guard let gpu, let starPipeline, let positionBuffer, let colorBuffer else { return }
        let width = Int(target.viewPx.x), height = Int(target.viewPx.y)
        let resized = hdr == nil || hdr!.width != width || hdr!.height != height
        if resized {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: true)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            hdr = gpu.device.makeTexture(descriptor: descriptor)
        }
        guard let hdr else { return }
        defer { starsDirty = false }
        if !starsDirty && !resized { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = hdr
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            var u = uniforms(target)
            encoder.setRenderPipelineState(starPipeline)
            encoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&u, length: MemoryLayout<FieldUniforms>.stride, index: 2)
            if count > 0 { encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count) }
            encoder.endEncoding()
        }
        commandBuffer.makeBlitCommandEncoder().map { $0.generateMipmaps(for: hdr); $0.endEncoding() }
    }

    public override func encode(_ target: RenderTarget, encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {
        guard let tonePipeline, let sampler, let hdr, let tiles, let labels else { return }
        var u = uniforms(target)
        encoder.setRenderPipelineState(tonePipeline)
        encoder.setFragmentTexture(hdr, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&u, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        let p = plot(target.viewPx, target.scale)
        let xTicks = visibleTicks(Self.ageTicks, xRange), yTicks = visibleTicks(Self.sizeTicks, yRange)
        tiles.encode(gridLines(p, xTicks, yTicks, target.scale) + brushInstances(target.scale), viewPx: target.viewPx, scale: target.scale, encoder: encoder)
        labels.atlas.beginFrame()
        let quads = axisLabels(labels.composer, p, xTicks, yTicks, target.scale)
        labels.encode(quads, viewPx: target.viewPx, encoder: encoder)
    }

    // MARK: Axes

    static let ageTicks: [(Float, String)] = [(0, "1 day"), (0.845, "1 week"), (1.477, "1 month"), (2.562, "1 year"), (3.261, "5 years")]
    static let sizeTicks: [(Float, String)] = [(3, "1 KB"), (5, "100 KB"), (6, "1 MB"), (8, "100 MB"), (9, "1 GB"), (11, "100 GB")]

    private func visibleTicks(_ ticks: [(Float, String)], _ range: ClosedRange<Float>) -> [(Float, String)] { ticks.filter { range.contains($0.0) } }

    private func x(of value: Float, _ p: SIMD4<Float>) -> Float { p.x + (value - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound) * p.z }
    private func y(of value: Float, _ p: SIMD4<Float>) -> Float { p.y + (1 - (value - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)) * p.w }

    private func flat(_ rect: SIMD4<Float>, _ color: SIMD3<Float>, _ alpha: Float) -> TileInstance {
        TileInstance(rect: rect, color: SIMD4(color, alpha), params: SIMD4(0, 3, 0, 0), state: .zero, extra: .zero)
    }

    /// Faint grid lines at each tick plus the two axes.
    private func gridLines(_ p: SIMD4<Float>, _ xTicks: [(Float, String)], _ yTicks: [(Float, String)], _ scale: Float) -> [TileInstance] {
        var lines = xTicks.map { flat(SIMD4(x(of: $0.0, p), p.y, scale, p.w), Palette.textPrimary, 0.06) }
        lines += yTicks.map { flat(SIMD4(p.x, y(of: $0.0, p), p.z, scale), Palette.textPrimary, 0.06) }
        lines.append(flat(SIMD4(p.x, p.y + p.w, p.z, scale), Palette.textSecondary, 0.28))
        lines.append(flat(SIMD4(p.x - scale, p.y, scale, p.w), Palette.textSecondary, 0.28))
        return lines
    }

    /// Tick labels in human units, plus the axis titles.
    private func axisLabels(_ composer: LabelComposer, _ p: SIMD4<Float>, _ xTicks: [(Float, String)], _ yTicks: [(Float, String)], _ scale: Float) -> [LabelQuad] {
        var quads: [LabelQuad] = []
        let size = 11.5 * scale
        for tick in xTicks {
            if let c = composer.caption(TextSpec(text: tick.1, size: size, tabular: true), x: x(of: tick.0, p), y: p.y + p.w + 10 * scale, available: 120 * scale,
                                        color: SIMD4(Palette.textSecondary, 1), align: .center) { quads.append(c.quad) }
        }
        for tick in yTicks {
            if let c = composer.caption(TextSpec(text: tick.1, size: size, tabular: true), x: p.x - 10 * scale, y: y(of: tick.0, p) - size * 0.65, available: 70 * scale,
                                        color: SIMD4(Palette.textSecondary, 1), align: .right) { quads.append(c.quad) }
        }
        if let c = composer.caption(TextSpec(text: "time since last modified  →", size: 11 * scale, weight: .medium), x: p.x + p.z, y: p.y + p.w + 34 * scale,
                                    available: 400 * scale, color: SIMD4(Palette.textMuted, 1), align: .right) { quads.append(c.quad) }
        if let c = composer.caption(TextSpec(text: "↑  size on disk", size: 11 * scale, weight: .medium), x: p.x, y: p.y - 24 * scale,
                                    available: 300 * scale, color: SIMD4(Palette.textMuted, 1), align: .left) { quads.append(c.quad) }
        return quads
    }

    /// The brush rectangle: a faint gold wash with a crisp edge.
    private func brushInstances(_ scale: Float) -> [TileInstance] {
        guard let brush else { return [] }
        let x0 = Float(min(brush.0.x, brush.1.x)), x1 = Float(max(brush.0.x, brush.1.x))
        let y0 = Float(min(brush.0.y, brush.1.y)), y1 = Float(max(brush.0.y, brush.1.y))
        let w = x1 - x0, h = y1 - y0, t = 1.5 * scale
        return [flat(SIMD4(x0, y0, w, h), Palette.accent, 0.07),
                flat(SIMD4(x0, y0, w, t), Palette.accent, 0.9), flat(SIMD4(x0, y1 - t, w, t), Palette.accent, 0.9),
                flat(SIMD4(x0, y0, t, h), Palette.accent, 0.9), flat(SIMD4(x1 - t, y0, t, h), Palette.accent, 0.9)]
    }

    // MARK: Input

    private func pixelPoint(_ event: NSEvent) -> SIMD2<Double> {
        let point = convert(event.locationInWindow, from: nil)
        return SIMD2(Double(point.x * backingScale), Double(point.y * backingScale))
    }

    private var currentPlot: SIMD4<Float> { plot(SIMD2(Float(viewPixels.x), Float(viewPixels.y)), Float(backingScale)) }

    /// The nearest large point within a few pixels of `point`.
    func node(atPx point: SIMD2<Double>) -> NodeID? {
        let p = currentPlot
        var best: (distance: Float, node: NodeID)?
        let limit = 11 * Float(backingScale)
        for index in candidates {
            let position = positions[Int(index)]
            let dx = x(of: position.x, p) - Float(point.x), dy = y(of: position.y, p) - Float(point.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < limit, best == nil || distance < best!.distance { best = (distance, nodes[Int(index)]) }
        }
        return best?.node
    }

    /// Converts a pixel rectangle inside the plot to data ranges.
    private func dataRanges(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> (ClosedRange<Float>, ClosedRange<Float>) {
        let p = currentPlot
        func age(_ px: Double) -> Float { xRange.lowerBound + (Float(px) - p.x) / p.z * (xRange.upperBound - xRange.lowerBound) }
        func size(_ py: Double) -> Float { yRange.lowerBound + (1 - (Float(py) - p.y) / p.w) * (yRange.upperBound - yRange.lowerBound) }
        let ageA = age(a.x), ageB = age(b.x), sizeA = size(a.y), sizeB = size(b.y)
        return (min(ageA, ageB)...max(ageA, ageB), min(sizeA, sizeB)...max(sizeA, sizeB))
    }

    private func clampToPlot(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let p = currentPlot
        return SIMD2(min(max(point.x, Double(p.x)), Double(p.x + p.z)), min(max(point.y, Double(p.y)), Double(p.y + p.w)))
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        let hit = node(atPx: pixelPoint(event))
        guard (hit ?? noNode) != hover else { return }
        hover = hit ?? noNode
        events.onHover?(hit, convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        guard hover != noNode else { return }
        hover = noNode
        events.onHover?(nil, .zero)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        brushStart = clampToPlot(pixelPoint(event))
        if event.clickCount == 2, let hit = node(atPx: pixelPoint(event)) { events.onDoubleClick?(hit) }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = brushStart else { return }
        brush = (start, clampToPlot(pixelPoint(event)))
        setNeedsRender()
    }

    public override func mouseUp(with event: NSEvent) {
        defer { brushStart = nil }
        guard let start = brushStart else { return }
        let end = clampToPlot(pixelPoint(event))
        if abs(end.x - start.x) > 4 * Double(backingScale) || abs(end.y - start.y) > 4 * Double(backingScale) {
            brush = (start, end)
            let ranges = dataRanges(start, end)
            events.onBrush?(ranges.0, ranges.1)
        } else {
            let hadBrush = brush != nil
            brush = nil
            if let hit = node(atPx: pixelPoint(event)) { events.onClick?(hit, event.modifierFlags) }
            if hadBrush { events.onBrush?(xRange, yRange) }
        }
        setNeedsRender()
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let hit = node(atPx: pixelPoint(event)) { events.onContextMenu?(hit, event) }
    }
}
