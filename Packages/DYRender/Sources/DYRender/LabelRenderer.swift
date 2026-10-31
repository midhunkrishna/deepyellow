import Foundation
import Metal
import simd

/// Draws `LabelQuad`s from a `LabelAtlas`, mirroring the atlas into a GPU texture. Reusable by any canvas.
public final class LabelRenderer {
    public let atlas: LabelAtlas
    public let composer: LabelComposer
    private let gpu: GPUContext
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let texture: MTLTexture
    private let ring: BufferRing

    /// Creates a renderer with its own atlas.
    public init(gpu: GPUContext) throws {
        self.gpu = gpu
        atlas = LabelAtlas()
        composer = LabelComposer(atlas: atlas)
        let library = try gpu.library(named: "tiles", source: Shaders.tiles)
        pipeline = try gpu.blendedPipeline(library: library, vertex: "labelVertex", fragment: "labelFragment")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: atlas.width, height: atlas.height, mipmapped: false)
        descriptor.usage = .shaderRead
        texture = gpu.device.makeTexture(descriptor: descriptor)!
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = gpu.device.makeSamplerState(descriptor: samplerDescriptor)!
        ring = BufferRing(device: gpu.device)
    }

    /// Uploads newly rasterised regions to the GPU texture.
    private func syncTexture() {
        atlas.pixels.withUnsafeBytes { bytes in
            for region in atlas.takeDirty() {
                texture.replace(region: MTLRegionMake2D(region.x, region.y, region.w, region.h), mipmapLevel: 0,
                                withBytes: bytes.baseAddress! + region.y * atlas.width + region.x, bytesPerRow: atlas.width)
            }
        }
    }

    /// Encodes the quads into an open render pass.
    public func encode(_ quads: [LabelQuad], viewPx: SIMD2<Float>, encoder: MTLRenderCommandEncoder) {
        syncTexture()
        guard !quads.isEmpty, let buffer = quads.withUnsafeBufferPointer({ ring.upload($0.baseAddress!, count: $0.count) }) else { return }
        var size = viewPx
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: quads.count)
    }
}
