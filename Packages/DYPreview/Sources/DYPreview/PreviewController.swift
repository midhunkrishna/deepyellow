import AVFoundation
import AppKit
import Foundation

/// Owns what the pane shows, and the video player. Changing item cancels work and releases the player.
@MainActor
public final class PreviewController: ObservableObject {
    @Published public private(set) var item: PreviewItem?
    @Published public private(set) var content: PreviewContent = .empty
    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var isPlaying = false
    /// Playback position as a fraction of the duration, 0...1.
    @Published public private(set) var playhead: Double = 0
    @Published public private(set) var zoomScale: CGFloat = 1
    /// Full-resolution decode, set only after the user zooms in.
    @Published public private(set) var fullImage: CGImage?
    public let filmstrip = FilmstripModel()
    /// Called when the user presses Download on a placeholder. The default asks iCloud to materialise the file.
    public var downloadHandler: (PreviewItem) -> Void = { item in
        try? FileManager.default.startDownloadingUbiquitousItem(at: item.url)
    }

    private let provider: PreviewContentProvider
    private var timeObserver: Any?
    private var observedPlayer: AVPlayer?
    private var fullImageTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    /// Creates a controller. Pass a provider with test loaders to observe what is loaded.
    public init(provider: PreviewContentProvider = PreviewContentProvider()) {
        self.provider = provider
    }

    /// Shows an item. Cancel the calling task to abandon the load; stale results are discarded.
    public func show(_ item: PreviewItem?) async {
        release()
        self.item = item
        guard let item else { content = .empty; return }
        content = .empty
        let loaded = await provider.content(for: item)
        guard !Task.isCancelled, self.item == item else { return }
        content = loaded
        if case .video(let url) = loaded { startPlayer(url) }
    }

    /// Starts or pauses the video.
    public func togglePlay() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    /// Moves the playhead by a number of seconds.
    public func seek(by seconds: Double) {
        guard let player else { return }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Moves the playhead to a fraction of the duration.
    public func seek(toFraction fraction: Double) {
        guard let player, let seconds = player.currentItem?.duration.seconds, seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: seconds * min(max(fraction, 0), 1), preferredTimescale: 600))
    }

    /// Multiplies the image zoom, clamped to 1...8. Zooming in decodes the full image once.
    public func zoom(by factor: Double) {
        setZoom(zoomScale * CGFloat(factor))
    }

    /// Sets the zoom directly, for pinch gestures that report an absolute value.
    public func setZoom(_ scale: CGFloat) {
        zoomScale = min(max(scale, 1), 8)
        guard zoomScale > 1.05, fullImage == nil, fullImageTask == nil, case .image = content, let item else { return }
        fullImageTask = Task { [provider] in
            let image = await provider.fullImage(for: item)
            if !Task.isCancelled, self.item == item { self.fullImage = image }
        }
    }

    /// Preloads the next few items so advancing is instant.
    public func prepare(_ upcoming: [PreviewItem]) {
        prepareTask?.cancel()
        prepareTask = Task { [provider] in await provider.prepare(upcoming) }
    }

    /// Asks for the placeholder to be downloaded. Only called from the explicit button.
    public func requestDownload() {
        if let item { downloadHandler(item) }
    }

    /// Pauses and releases the player, cancels decoding and clears zoom.
    public func release() {
        fullImageTask?.cancel()
        fullImageTask = nil
        fullImage = nil
        zoomScale = 1
        filmstrip.reset()
        if let observedPlayer, let timeObserver { observedPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observedPlayer = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        playhead = 0
    }

    /// Creates a paused player and a time observer feeding `playhead`.
    private func startPlayer(_ url: URL) {
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self, weak player] time in
            guard let total = player?.currentItem?.duration.seconds, total.isFinite, total > 0 else { return }
            MainActor.assumeIsolated { self?.playhead = time.seconds / total }
        }
        observedPlayer = player
        self.player = player
        filmstrip.load(url: url)
    }
}
