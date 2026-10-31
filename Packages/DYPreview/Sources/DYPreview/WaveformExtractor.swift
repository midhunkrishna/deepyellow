import AVFoundation
import Foundation

/// Peak amplitudes of an audio file, normalised to 0...1.
public struct Waveform: Sendable, Equatable {
    public var peaks: [Float]
    public var duration: Double
    public init(peaks: [Float], duration: Double) {
        self.peaks = peaks
        self.duration = duration
    }
}

/// Builds waveforms with `AVAssetReader`.
public enum WaveformExtractor {
    static let sampleRate = 8000.0

    /// Decodes to mono 16-bit PCM at 8 kHz and returns the peak of each of `buckets` slices. Nil when the file
    /// can't be decoded. Honours cancellation.
    public static func extract(from url: URL, buckets: Int = 200) async -> Waveform? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0,
              let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: sampleRate,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        let total = max(1, Int(duration * sampleRate))
        var peaks = [Float](repeating: 0, count: buckets)
        var index = 0
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [Int16](repeating: 0, count: length / 2)
            _ = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length / 2 * 2, destination: $0.baseAddress!) }
            for sample in bytes {
                let bucket = min(buckets - 1, index * buckets / total)
                peaks[bucket] = max(peaks[bucket], abs(Float(sample)) / 32768)
                index += 1
            }
        }
        guard index > 0 else { return nil }
        let top = peaks.max() ?? 0
        if top > 0 { peaks = peaks.map { $0 / top } }
        return Waveform(peaks: peaks, duration: duration)
    }
}
