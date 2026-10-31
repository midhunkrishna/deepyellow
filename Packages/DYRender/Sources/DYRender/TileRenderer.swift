import DYCore
import Foundation
import Metal
import simd

/// Palette colours and metrics the tile shader needs. Must match `Uniforms` in the shader source.
struct TileUniforms {
    var viewSize: SIMD2<Float>
    var gap: Float
    var scale: Float
    var background: SIMD4<Float>, surface: SIMD4<Float>, accent: SIMD4<Float>
    var removeColor: SIMD4<Float>, keepColor: SIMD4<Float>, laterColor: SIMD4<Float>, text: SIMD4<Float>
}

/// Draws instanced SDF rounded rects. Reusable for any canvas that wants lit tiles.
public final class TileRenderer {
    private let pipeline: MTLRenderPipelineState
    private let ring: BufferRing

    /// Compiles the tile pipeline.
    public init(gpu: GPUContext) throws {
        let library = try gpu.library(named: "tiles", source: Shaders.tiles)
        pipeline = try gpu.blendedPipeline(library: library, vertex: "tileVertex", fragment: "tileFragment")
        ring = BufferRing(device: gpu.device)
    }

    private static func rgba(_ color: SIMD3<Float>) -> SIMD4<Float> { SIMD4(color, 1) }

    /// Encodes all tiles into an open render pass.
    public func encode(_ tiles: [TileInstance], viewPx: SIMD2<Float>, scale: Float, encoder: MTLRenderCommandEncoder) {
        guard !tiles.isEmpty, let buffer = tiles.withUnsafeBufferPointer({ ring.upload($0.baseAddress!, count: $0.count) }) else { return }
        var uniforms = TileUniforms(viewSize: viewPx, gap: scale, scale: scale, background: Self.rgba(Palette.background),
                                    surface: Self.rgba(Palette.surface), accent: Self.rgba(Palette.accent),
                                    removeColor: Self.rgba(Palette.remove), keepColor: Self.rgba(Palette.keep),
                                    laterColor: Self.rgba(Palette.later), text: Self.rgba(Palette.textPrimary))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 1)
        encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: tiles.count)
    }
}
