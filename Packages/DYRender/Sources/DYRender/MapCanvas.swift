import AppKit
import DYCore
import Metal
import QuartzCore
import simd

/// The zoomable treemap: tiles are Metal instances, text comes from a CoreText atlas, and layout is lazy and world-space.
public final class MapCanvas: MetalCanvasView, DiskCanvas {
    public var events = CanvasEvents()
    public let model = MapModel()
    private var tileRenderer: TileRenderer?
    private var labelRenderer: LabelRenderer?
    private var trackingArea: NSTrackingArea?
    private var reportedFocus: NodeID = noNode
    private var dragDistance: CGFloat = 0
    private var currentLens: TreeLens?
    /// CPU seconds spent building the last frame's scene, for benchmarks.
    public private(set) var lastSceneSeconds: Double = 0
    /// Number of tiles and labels in the last frame.
    public private(set) var lastCounts = (tiles: 0, labels: 0)

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setUpRenderers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpRenderers()
    }

    private func setUpRenderers() {
        guard let gpu else { return }
        tileRenderer = try? TileRenderer(gpu: gpu)
        labelRenderer = try? LabelRenderer(gpu: gpu)
    }

    // MARK: DiskCanvas

    public func update(lens: TreeLens, style: NodeStyle, metric: Metric, selection: Set<NodeID>, animated: Bool) {
        let now = CACurrentMediaTime()
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        currentLens = lens
        model.setContent(lens: lens, style: style, metric: metric, selection: selection, animated: animated,
                         viewPx: effectivePixels, scale: Double(backingScale), now: now)
        if animated, !model.reduceMotion { startAnimating() } else { setNeedsRender() }
    }

    public func focus(on node: NodeID, animated: Bool) {
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.focus(on: node, animated: animated, viewPx: effectivePixels, now: CACurrentMediaTime())
        if animated, !model.reduceMotion { startAnimating() } else { setNeedsRender() }
    }

    /// Where each visible child of `parent` sits on the map, for moving between tiles by what is next to them.
    public func levelRects(parent: NodeID) -> [NodeID: CGRect] {
        guard let layout = model.ensureLayout(viewPx: effectivePixels) else { return [:] }
        return layout.childRects(of: parent).mapValues { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
    }

    public func snapshot(size: CGSize, scale: CGFloat) -> CGImage? {
        renderOffscreen(size: size, scale: scale).image
    }

    /// The view size in pixels, or a sensible default before the view has a size.
    private var effectivePixels: SIMD2<Double> {
        let pixels = viewPixels
        return pixels.x > 0 && pixels.y > 0 ? pixels : SIMD2(1600, 1000)
    }

    // MARK: Drawing

    public override func step(now: CFTimeInterval) -> Bool { model.step(now: now) }

    public override func encode(_ target: RenderTarget, encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {
        guard let tileRenderer, let labelRenderer, let lens = currentLens else { return }
        let viewPx = SIMD2<Double>(Double(target.viewPx.x), Double(target.viewPx.y))
        let started = CACurrentMediaTime()
        if lens !== model.lens { return }
        let scene = model.buildScene(viewPx: viewPx, scale: Double(target.scale), now: target.time)
        let quads = labelRenderer.composer.compose(scene.labels, lens: lens, metric: model.metric, scale: target.scale)
        lastSceneSeconds = CACurrentMediaTime() - started
        lastCounts = (scene.tiles.count, quads.count)
        tileRenderer.encode(scene.tiles, viewPx: target.viewPx, scale: target.scale, encoder: encoder)
        let plates = labelRenderer.composer.plates.map { plate in
            TileInstance(rect: SIMD4(plate.x, plate.y, plate.z, plate.w), color: SIMD4(Palette.background * 1.25, 0.88),
                         params: SIMD4(5 * target.scale, 3, 0, 0), state: .zero, extra: .zero)
        }
        tileRenderer.encode(plates, viewPx: target.viewPx, scale: target.scale, encoder: encoder)
        labelRenderer.encode(quads, viewPx: target.viewPx, encoder: encoder)
        if scene.focusNode != reportedFocus {
            reportedFocus = scene.focusNode
            let node = scene.focusNode
            DispatchQueue.main.async { [weak self] in self?.events.onFocusChanged?(node) }
        }
    }

    // MARK: Input

    private func pixelPoint(_ event: NSEvent) -> SIMD2<Double> {
        let p = convert(event.locationInWindow, from: nil)
        return SIMD2(Double(p.x * backingScale), Double(p.y * backingScale))
    }

    private func node(at event: NSEvent) -> NodeID? { model.hitTest(px: pixelPoint(event)) }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        let hit = node(at: event)
        guard (hit ?? noNode) != model.hover else { return }
        model.hover = hit ?? noNode
        setNeedsRender()
        events.onHover?(hit, convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        guard model.hover != noNode else { return }
        model.hover = noNode
        setNeedsRender()
        events.onHover?(nil, .zero)
    }

    public override func mouseDown(with event: NSEvent) {
        dragDistance = 0
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        if event.clickCount == 2, let hit = node(at: event) {
            events.onDoubleClick?(hit)
            focus(on: hit, animated: true)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        dragDistance += abs(event.deltaX) + abs(event.deltaY)
        model.pan(byPx: SIMD2(Double(event.deltaX * backingScale), Double(event.deltaY * backingScale)), viewPx: effectivePixels)
        setNeedsRender()
    }

    public override func mouseUp(with event: NSEvent) {
        guard dragDistance < 3, event.clickCount == 1, let hit = node(at: event) else { return }
        events.onClick?(hit, event.modifierFlags)
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let hit = node(at: event) { events.onContextMenu?(hit, event) }
    }

    public override func scrollWheel(with event: NSEvent) {
        let sensitivity = event.hasPreciseScrollingDeltas ? 0.0035 : 0.045
        let delta = event.scrollingDeltaY * sensitivity
        guard delta != 0 else { return }
        model.zoom(by: exp(Double(delta)), anchorPx: pixelPoint(event), viewPx: effectivePixels)
        setNeedsRender()
    }

    public override func magnify(with event: NSEvent) {
        model.zoom(by: exp(Double(event.magnification) * 1.6), anchorPx: pixelPoint(event), viewPx: effectivePixels)
        setNeedsRender()
    }
}
