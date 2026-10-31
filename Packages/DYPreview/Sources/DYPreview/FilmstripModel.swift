import AVFoundation
import AppKit
import Foundation

/// Lazily generated filmstrip frames and the hover-scrub frame for one video.
@MainActor
public final class FilmstripModel: ObservableObject {
    @Published public private(set) var frames: [CGImage?] = []
    @Published public private(set) var hoverFrame: CGImage?
    private var generator: AVAssetImageGenerator?
    private var duration: Double = 0
    private var stripTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?

    public init() {}

    /// Starts generating `count` frames for a video. Any earlier work is cancelled first.
    public func load(url: URL, count: Int = 12) {
        reset()
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        self.generator = generator
        frames = Array(repeating: nil, count: count)
        stripTask = Task { [weak self] in
            guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 else { return }
            self?.duration = seconds
            for index in 0..<count {
                if Task.isCancelled { return }
                let time = CMTime(seconds: seconds * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
                let image = try? await generator.image(at: time).image
                if Task.isCancelled { return }
                self?.set(frame: image, at: index)
            }
        }
    }

    /// Shows the frame at a fraction (0...1) of the video. Each call cancels the previous request.
    public func scrub(to fraction: Double?) {
        hoverTask?.cancel()
        guard let fraction, let generator, duration > 0 else { hoverFrame = nil; return }
        hoverTask = Task { [weak self] in
            let time = CMTime(seconds: (self?.duration ?? 0) * min(max(fraction, 0), 1), preferredTimescale: 600)
            let image = try? await generator.image(at: time).image
            if !Task.isCancelled { self?.hoverFrame = image }
        }
    }

    /// Cancels all work and drops every frame.
    public func reset() {
        stripTask?.cancel()
        hoverTask?.cancel()
        generator?.cancelAllCGImageGeneration()
        generator = nil
        frames = []
        hoverFrame = nil
        duration = 0
    }

    private func set(frame: CGImage?, at index: Int) {
        if index < frames.count { frames[index] = frame }
    }
}
