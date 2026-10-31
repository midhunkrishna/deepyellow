import AppKit
import DYCore
import Metal
import QuartzCore
import simd

/// What a canvas draws into for one frame.
public struct RenderTarget {
    public var viewPx: SIMD2<Float>
    public var scale: Float
    public var time: CFTimeInterval
}

/// An `NSView` backed by a `CAMetalLayer` that draws only on demand.
///
/// Nothing runs while idle: there is no display link until `startAnimating()`, and it stops itself as soon as
/// `step(now:)` reports nothing is moving. Subclasses override `encode` and optionally `step`.
open class MetalCanvasView: NSView {
    public let gpu: GPUContext?
    private var displayLink: CADisplayLink?
    private var renderPending = false
    /// Whether a display link is running. False at idle, which is what keeps idle GPU cost at zero.
    public var isAnimating: Bool { displayLink != nil }
    /// GPU time of the most recent on-screen frame, in seconds.
    public private(set) var lastGPUSeconds: Double = 0

    public override init(frame: NSRect) {
        gpu = GPUContext.shared
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        gpu = GPUContext.shared
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let metal = layer as? CAMetalLayer else { return }
        metal.device = gpu?.device
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metal.isOpaque = true
        metal.backgroundColor = CGColor(red: 0.055, green: 0.051, blue: 0.043, alpha: 1)
        metal.maximumDrawableCount = 3
    }

    open override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    open override var isFlipped: Bool { true }
    open override var acceptsFirstResponder: Bool { true }
    open override var isOpaque: Bool { true }

    /// Encodes this canvas's drawing into an open render pass cleared to the background colour.
    open func encode(_ target: RenderTarget, encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {}

    /// Encodes any offscreen passes that must finish before the main pass. Called with no encoder open.
    open func prepare(_ target: RenderTarget, commandBuffer: MTLCommandBuffer) {}

    /// Advances animation to `now`. Return true to keep the display link running.
    open func step(now: CFTimeInterval) -> Bool { false }

    /// Pixels per point for this view's window.
    public var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// The view's size in device pixels.
    public var viewPixels: SIMD2<Double> { SIMD2(Double(bounds.width * backingScale), Double(bounds.height * backingScale)) }

    open override func layout() {
        super.layout()
        updateDrawableSize()
        drawNow()
    }

    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        (layer as? CAMetalLayer)?.contentsScale = backingScale
        updateDrawableSize()
        setNeedsRender()
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimating() } else { setNeedsRender() }
    }

    private func updateDrawableSize() {
        guard let metal = layer as? CAMetalLayer else { return }
        metal.contentsScale = backingScale
        metal.drawableSize = CGSize(width: max(1, bounds.width * backingScale), height: max(1, bounds.height * backingScale))
    }

    /// Schedules one draw on the next run-loop turn. Repeated calls coalesce.
    public func setNeedsRender() {
        guard !renderPending, displayLink == nil else { return }
        renderPending = true
        DispatchQueue.main.async { [weak self] in
            self?.renderPending = false
            self?.drawNow()
        }
    }

    /// Starts the display link. It stops by itself once `step(now:)` returns false.
    public func startAnimating() {
        guard displayLink == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stops the display link, returning the canvas to zero GPU work.
    public func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let keepGoing = step(now: link.targetTimestamp)
        drawNow()
        if !keepGoing { stopAnimating() }
    }

    /// Draws one frame to the window.
    public func drawNow() {
        guard let gpu, let metal = layer as? CAMetalLayer, bounds.width > 0, bounds.height > 0,
              window?.occlusionState.contains(.visible) ?? true,
              let drawable = metal.nextDrawable(), let commands = gpu.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        Self.configure(pass, texture: drawable.texture)
        let size = SIMD2(Float(drawable.texture.width), Float(drawable.texture.height))
        let target = RenderTarget(viewPx: size, scale: Float(backingScale), time: CACurrentMediaTime())
        prepare(target, commandBuffer: commands)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(target, encoder: encoder, commandBuffer: commands)
        encoder.endEncoding()
        commands.addCompletedHandler { [weak self] buffer in self?.lastGPUSeconds = buffer.gpuEndTime - buffer.gpuStartTime }
        commands.present(drawable)
        commands.commit()
    }

    private static func configure(_ pass: MTLRenderPassDescriptor, texture: MTLTexture) {
        let background = Palette.background
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(background.x), green: Double(background.y), blue: Double(background.z), alpha: 1)
    }

    /// Renders one frame offscreen with no window, optionally reading it back. Returns the GPU time too.
    public func renderOffscreen(size: CGSize, scale: CGFloat, readBack: Bool = true) -> (image: CGImage?, gpuSeconds: Double) {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let gpu, width > 0, height > 0, let texture = gpu.makeTarget(width: width, height: height),
              let commands = gpu.queue.makeCommandBuffer() else { return (nil, 0) }
        let pass = MTLRenderPassDescriptor()
        Self.configure(pass, texture: texture)
        let target = RenderTarget(viewPx: SIMD2(Float(width), Float(height)), scale: Float(scale), time: CACurrentMediaTime())
        prepare(target, commandBuffer: commands)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return (nil, 0) }
        encode(target, encoder: encoder, commandBuffer: commands)
        encoder.endEncoding()
        if readBack, !gpu.device.hasUnifiedMemory, let blit = commands.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        commands.commit()
        commands.waitUntilCompleted()
        let gpuSeconds = commands.gpuEndTime - commands.gpuStartTime
        return (readBack ? Self.image(from: texture) : nil, gpuSeconds)
    }

    private static func image(from texture: MTLTexture) -> CGImage? {
        let width = texture.width, height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
