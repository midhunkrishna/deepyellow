import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates small media files for the demo and tests. Writes only inside the directory it is given.
public enum PreviewFixtures {
    /// Writes a gradient PNG.
    public static func image(at url: URL, width: Int = 640, height: Int = 360) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 1, green: 0.72, blue: 0, alpha: 1), CGColor(red: 0.3, green: 0.1, blue: 0.4, alpha: 1)]
        let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        guard let image = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Writes a one-page PDF containing a line of text.
    public static func pdf(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0.72, blue: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 220, height: 320))
        context.endPDFPage()
        context.closePDF()
    }

    /// Writes a text file of roughly `bytes` bytes.
    public static func text(at url: URL, bytes: Int = 1000) throws {
        let line = "The quick brown fox jumps over the lazy dog.\n"
        try String(repeating: line, count: max(1, bytes / line.utf8.count)).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes a sine-wave WAV whose amplitude ramps up, so the waveform has visible shape.
    public static func audio(at url: URL, seconds: Double = 2) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 1, interleaved: true)!
        let frames = AVAudioFrameCount(seconds * 8000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.int16ChannelData![0]
        for i in 0..<Int(frames) {
            let ramp = Double(i) / Double(frames)
            samples[i] = Int16(sin(Double(i) * 0.1) * 30000 * ramp)
        }
        try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            .write(from: buffer)
    }

    /// Writes an H.264 MOV with moving colour bars.
    public static func video(at url: URL, seconds: Int = 2, fps: Int = 10) async throws {
        let size = 320
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<size { for x in 0..<size {
                let p = base + y * stride + x * 4
                p[0] = UInt8((x + frame * 8) % 256); p[1] = UInt8(y % 256); p[2] = UInt8(frame * 255 / max(1, seconds * fps)); p[3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
