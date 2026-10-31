import CoreGraphics
import Foundation

/// Loads and caches what each item displays. Failures fall back to QuickLook and never throw.
public actor PreviewContentProvider {
    private let loaders: PreviewLoaders
    private let screenSide: CGFloat
    private var cache: LRUCache<URL, PreviewContent>
    private var waveforms: LRUCache<URL, Waveform>
    private var inFlight: [URL: Task<PreviewContent, Never>] = [:]
    public let prepareLimit: Int

    /// Creates a provider. `screenSide` is the long edge in pixels used for the first image decode.
    public init(loaders: PreviewLoaders = .live, screenSide: CGFloat = 2880, cacheSize: Int = 6, prepareLimit: Int = 3) {
        self.loaders = loaders
        self.screenSide = screenSide
        cache = LRUCache(maxCost: cacheSize)
        waveforms = LRUCache(maxCost: 64)
        self.prepareLimit = prepareLimit
    }

    /// Number of cached items.
    public var cachedCount: Int { cache.count }

    /// Whether an item is already loaded.
    public func isCached(_ item: PreviewItem) -> Bool { cache.contains(item.url) }

    /// Returns the content for an item, from cache when possible. Dataless items return at once without calling a loader.
    public func content(for item: PreviewItem) async -> PreviewContent {
        let route = PreviewRoute.route(for: item)
        if route == .dataless { return .dataless }
        if route == .directory { return .directory(item.largestChildren) }
        if let hit = cache.get(item.url) { return hit }
        if let running = inFlight[item.url] { return await running.value }
        let task = Task { await load(item, route: route) }
        inFlight[item.url] = task
        let result = await task.value
        inFlight[item.url] = nil
        if !Task.isCancelled { cache.set(item.url, result) }
        return result
    }

    /// Preloads at most `prepareLimit` upcoming items and cancels earlier preloads that fell out of that window.
    public func prepare(_ upcoming: [PreviewItem]) {
        let wanted = Array(upcoming.prefix(prepareLimit)).filter { !$0.isDataless && !$0.isDirectory }
        let urls = Set(wanted.map(\.url))
        for (url, task) in inFlight where !urls.contains(url) { task.cancel() }
        for item in wanted where !cache.contains(item.url) && inFlight[item.url] == nil {
            Task { _ = await self.content(for: item) }
        }
    }

    /// Decodes the whole image for zoom. Returns nil for dataless items.
    public func fullImage(for item: PreviewItem) async -> CGImage? {
        guard !item.isDataless else { return nil }
        return await loaders.image(item.url, 0)
    }

    /// Runs the loader for a route and maps failure to QuickLook.
    private func load(_ item: PreviewItem, route: PreviewRoute) async -> PreviewContent {
        let url = item.url
        let fallback = PreviewContent.quickLook(url)
        switch route {
        case .video: return await loaders.isPlayable(url) ? .video(url) : fallback
        case .image: return await loaders.image(url, screenSide).map { .image($0) } ?? fallback
        case .pdf: return await loaders.pdfPageCount(url) > 0 ? .pdf(url) : fallback
        case .text: return await loaders.text(url).map { .text($0) } ?? fallback
        case .audio: return await audio(url) ?? fallback
        case .quickLook, .dataless, .directory: return fallback
        }
    }

    /// Returns a cached or freshly extracted waveform as content.
    private func audio(_ url: URL) async -> PreviewContent? {
        if let hit = waveforms.get(url) { return .audio(hit) }
        guard let wave = await loaders.waveform(url) else { return nil }
        waveforms.set(url, wave)
        return .audio(wave)
    }
}
