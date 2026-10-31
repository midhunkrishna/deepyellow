import Foundation
import Metal

/// The process-wide Metal device, queue and pipeline compiler shared by every canvas.
public final class GPUContext {
    /// The shared context, or nil on a machine without Metal.
    public static let shared: GPUContext? = GPUContext()
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    private var libraries: [String: MTLLibrary] = [:]
    private let lock = NSLock()

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
    }

    /// Compiles (once per `name`) Metal source into a library.
    public func library(named name: String, source: String) throws -> MTLLibrary {
        lock.lock(); defer { lock.unlock() }
        if let cached = libraries[name] { return cached }
        let library = try device.makeLibrary(source: source, options: nil)
        libraries[name] = library
        return library
    }

    /// Builds a render pipeline drawing alpha-blended instances into a bgra8 target.
    public func blendedPipeline(library: MTLLibrary, vertex: String, fragment: String) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Creates a texture suitable as an offscreen render target that can be read back.
    public func makeTarget(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        return device.makeTexture(descriptor: descriptor)
    }
}

/// A ring of upload buffers so the CPU can write the next frame while the GPU reads the previous ones.
public final class BufferRing {
    private let device: MTLDevice
    private var buffers: [MTLBuffer?]
    private var index = 0

    /// Creates a ring of `depth` slots.
    public init(device: MTLDevice, depth: Int = 3) { self.device = device; buffers = Array(repeating: nil, count: depth) }

    /// Copies `count` elements of `T` into the next slot, growing it if needed, and returns the buffer.
    public func upload<T>(_ elements: UnsafePointer<T>, count: Int) -> MTLBuffer? {
        index = (index + 1) % buffers.count
        let length = max(count * MemoryLayout<T>.stride, 256)
        if buffers[index] == nil || buffers[index]!.length < length {
            buffers[index] = device.makeBuffer(length: length * 3 / 2, options: .storageModeShared)
        }
        guard let buffer = buffers[index] else { return nil }
        if count > 0 { memcpy(buffer.contents(), elements, count * MemoryLayout<T>.stride) }
        return buffer
    }
}
