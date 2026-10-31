import AVFoundation
import CoreGraphics
import CoreText
import DYCore
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Sample media for the sample disk. Nothing on the sample disk exists on a real disk, so previews play these generated files instead.
/// They are drawn procedurally, labelled as samples, and written once into `<data directory>/demo-media`.
public enum DemoMedia {
    static let videoNames = ["sample-video-1.mp4", "sample-video-2.mp4"]
    static let imageNames = ["sample-photo-1.jpg", "sample-photo-2.jpg", "sample-photo-3.jpg"]
    static let audioName = "sample-tone.wav"
    static let pdfName = "sample-document.pdf"

    /// The folder holding the generated files.
    public static func folder(in dataDirectory: URL) -> URL { dataDirectory.appendingPathComponent("demo-media", isDirectory: true) }

    /// Picks the sample file for a sample-disk file of `kind`. Returns nil when that file hasn't been generated, so the preview falls
    /// back to metadata only.
    public static func locator(in folder: URL) -> @Sendable (String, FileKind) -> URL? {
        { path, kind in
            let seed = path.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
            let name: String?
            switch kind {
            case .video: name = videoNames[abs(seed) % videoNames.count]
            case .image: name = imageNames[abs(seed) % imageNames.count]
            case .audio: name = audioName
            case .document: name = path.lowercased().hasSuffix(".pdf") ? pdfName : nil
            default: name = nil
            }
            guard let name else { return nil }
            let url = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// Generates every missing sample file. Safe to call again.
    public static func ensure(in folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, name) in videoNames.enumerated() where !exists(folder, name) {
            try? await makeVideo(at: folder.appendingPathComponent(name), variant: index)
        }
        for (index, name) in imageNames.enumerated() where !exists(folder, name) { makeImage(at: folder.appendingPathComponent(name), variant: index) }
        if !exists(folder, audioName) { makeTone(at: folder.appendingPathComponent(audioName)) }
        if !exists(folder, pdfName) { makePDF(at: folder.appendingPathComponent(pdfName)) }
    }

    private static func exists(_ folder: URL, _ name: String) -> Bool {
        (try? folder.appendingPathComponent(name).checkResourceIsReachable()) == true
    }

    // MARK: Video

    /// Writes a six second H.264 clip of a drifting landscape.
    static func makeVideo(at url: URL, variant: Int) async throws {
        let width = 1280, height = 720, fps = 24, frames = fps * 6
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                drawLandscape(context, width: Double(width), height: Double(height), t: Double(frame) / Double(frames), variant: variant)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    // MARK: Image

    /// Writes a 1600 by 1000 JPEG of the same landscape.
    static func makeImage(at url: URL, variant: Int) {
        let width = 1600, height = 1000
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        drawLandscape(context, width: Double(width), height: Double(height), t: 0.15 + 0.3 * Double(variant), variant: variant + 1)
        guard let image = context.makeImage() else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// Draws sky, sun, three ridges and a label. `t` runs 0 to 1 and moves the sun and the ridges.
    static func drawLandscape(_ c: CGContext, width w: Double, height h: Double, t: Double, variant: Int) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let skies: [[CGFloat]] = [[0.99, 0.72, 0.30, 1, 0.16, 0.20, 0.38, 1], [0.95, 0.55, 0.40, 1, 0.10, 0.17, 0.33, 1], [0.98, 0.84, 0.50, 1, 0.20, 0.34, 0.52, 1]]
        let sky = skies[variant % skies.count]
        if let gradient = CGGradient(colorSpace: space, colorComponents: sky, locations: [0, 1], count: 2) {
            c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h * 0.35), end: CGPoint(x: 0, y: h), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        }
        let sunX = w * (0.2 + 0.6 * t), sunY = h * (0.52 + 0.1 * sin(t * .pi))
        c.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.7, alpha: 0.95))
        c.fillEllipse(in: CGRect(x: sunX - h * 0.09, y: sunY - h * 0.09, width: h * 0.18, height: h * 0.18))
        let layers: [(base: Double, amp: Double, speed: Double, shade: CGFloat)] = [(0.42, 0.10, 0.6, 0.45), (0.30, 0.12, 1.1, 0.30), (0.18, 0.08, 1.8, 0.14)]
        for (index, layer) in layers.enumerated() {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            var x = 0.0
            while x <= w + 8 {
                let u = x / w * 6 + t * layer.speed * 2 + Double(index * 3 + variant)
                let y = h * (layer.base + layer.amp * (0.6 * sin(u) + 0.4 * sin(u * 2.3 + 1.7)))
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            path.addLine(to: CGPoint(x: w + 8, y: 0))
            path.closeSubpath()
            c.setFillColor(CGColor(red: 0.35 * layer.shade, green: 0.30 * layer.shade + 0.04, blue: 0.40 * layer.shade + 0.06, alpha: 1))
            c.addPath(path)
            c.fillPath()
        }
        drawText("Sample media from DeepYellow's sample disk", in: c, at: CGPoint(x: h * 0.03, y: h * 0.03), size: h * 0.035, alpha: 0.85)
    }

    /// Draws one line of text.
    static func drawText(_ text: String, in c: CGContext, at point: CGPoint, size: Double, alpha: CGFloat, color: CGColor? = nil) {
        let font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color ?? CGColor(red: 1, green: 1, blue: 1, alpha: alpha),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        c.textPosition = point
        CTLineDraw(line, c)
    }

    // MARK: Audio and PDF

    /// Writes four seconds of a decaying A minor arpeggio as 16-bit mono WAV.
    static func makeTone(at url: URL) {
        let rate = 44_100, seconds = 4
        let notes = [220.0, 261.63, 329.63, 440.0]
        var samples = [Int16](repeating: 0, count: rate * seconds)
        for i in samples.indices {
            let time = Double(i) / Double(rate)
            let step = Int(time / 0.25), local = time - Double(step) * 0.25
            let frequency = notes[step % notes.count] * (step % 8 >= 4 ? 2 : 1)
            samples[i] = Int16(sin(2 * .pi * frequency * time) * exp(-local * 7) * 0.5 * Double(Int16.max))
        }
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + samples.count * 2)); data.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(samples.count * 2))
        for sample in samples { put(sample) }
        try? data.write(to: url)
    }

    /// Writes a one-page PDF saying what it is.
    static func makePDF(at url: URL) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.12, green: 0.1, blue: 0.08, alpha: 1))
        drawText("Sample document", in: context, at: CGPoint(x: 72, y: 700), size: 28, alpha: 1, color: CGColor(red: 0.12, green: 0.1, blue: 0.08, alpha: 1))
        context.setFillColor(CGColor(red: 0.3, green: 0.28, blue: 0.25, alpha: 1))
        drawText("Generated by DeepYellow for the sample disk.", in: context, at: CGPoint(x: 72, y: 660), size: 14, alpha: 1, color: CGColor(red: 0.3, green: 0.28, blue: 0.25, alpha: 1))
        context.endPDFPage()
        context.closePDF()
    }
}
