import DYAdvisor
import DYAnalysis
import DYCore
import DYScan
import Foundation

/// Source selection, the scan lifecycle, the scan cache and the background analyses that follow a scan.
extension Workspace {
    // MARK: - Opening

    /// Opens a source, cancelling whatever was running. A path opens its cached scan at once when there is one, then rescans.
    public func open(_ source: WorkspaceSource, useCache: Bool = true) {
        cancelEverything()
        self.source = source
        resetForNewSource()
        taskEpoch += 1
        switch source {
        case .demo:
            guard let sample = environment.sampleDisk else {
                post("The sample disk isn't available in this session.")
                return
            }
            scanPhase = .scanning
            scanTask = Task { [weak self] in
                let tree = await Task.detached { sample() }.value
                guard let self, !Task.isCancelled else { return }
                self.finishScan(tree, fresh: true)
            }
        case .path(let root):
            scanPhase = .scanning
            scanTask = Task { [weak self] in await self?.runScan(root: root, useCache: useCache) }
        }
    }

    /// Whether the open folder can be scanned again now.
    public var canRescan: Bool {
        guard case .path = source else { return false }
        return scanPhase != .scanning && scanPhase != .loadingCache
    }

    /// Scans the open folder again, skipping the cached scan. The folder you are in, the selection and a SQL result carry over.
    public func rescan() {
        guard canRescan, case .path(let root)? = source else { return }
        let (place, selected, primary, hadSQL) = (focusPath, selectionPaths, primarySelectionPath, sqlResult != nil)
        open(.path(root), useCache: false)
        focusPath = place
        selectionPaths = selected
        primarySelectionPath = primary
        if hadSQL { sqlPhase = .running }
    }

    /// Stops a running scan. The partial tree is kept unless a cached scan is on screen.
    public func cancelScan() {
        guard scanPhase == .scanning || scanPhase == .loadingCache else { return }
        scanWasCancelled = true
        scanCancel?()
    }

    /// Cancels scans, analyses and view work.
    func cancelEverything() {
        scanWasCancelled = false
        scanCancel?()
        scanTask?.cancel()
        lensToken?.cancel()
        viewToken?.cancel()
        sqlToken?.cancel()
        cancelAnalyses()
        worklistToken?.cancel()
        refineToken?.cancel()
    }

    /// Clears everything derived from the previous source.
    func resetForNewSource() {
        tree = nil
        lens = nil
        baseLens = nil
        resolved = nil
        markedFiles = []
        plan = nil
        lastExecution = nil
        dominantKinds = []
        scanProgress = nil
        scanPhase = .idle
        isLiveSnapshot = false
        isShowingCachedScan = false
        trashedPaths = []
        selectionPaths = []
        primarySelectionPath = nil
        review = nil
        focus = 0
        focusPath = "/"
        cachedIgnore = nil
        resetSQL()
        resetAnalyses()
        refreshSelection()
    }

    /// Clears analysis outputs, which belong to one tree.
    func resetAnalyses() {
        reclaimReport = nil
        ownershipReport = nil
        kindRefinement = nil
        duplicateReport = nil
        worklists = []
        things = nil
        spectrum = nil
        field = nil
        analysis = [:]
    }

    // MARK: - Scanning

    /// Shows the cached scan if one exists, then scans and replaces it when the scan finishes.
    private func runScan(root: String, useCache: Bool) async {
        if useCache, environment.savesScanCache {
            scanPhase = .loadingCache
            let url = cacheURL(forRoot: root)
            if let cached = await Task.detached(operation: { try? ScanCache.load(from: url) }).value, !Task.isCancelled {
                isShowingCachedScan = true
                adopt(cached)
                startAnalysis()
            }
        }
        scanPhase = .scanning
        let handle = environment.startScan(root)
        scanCancel = handle.cancel
        for await event in handle.events {
            if Task.isCancelled { handle.cancel(); break }
            switch event {
            case .progress(let progress): scanProgress = progress
            case .snapshot(let snapshot):
                guard !isShowingCachedScan else { continue }
                isLiveSnapshot = true
                adopt(snapshot)
            case .finished(let finished):
                if scanWasCancelled, isShowingCachedScan { scanPhase = .finished; return }
                finishScan(finished, fresh: !scanWasCancelled)
            }
        }
        if scanPhase == .scanning { scanPhase = .finished }
    }

    /// Takes the final tree of a scan: caches it and starts the analyses.
    func finishScan(_ finished: FileTree, fresh: Bool) {
        isLiveSnapshot = false
        isShowingCachedScan = false
        if fresh { trashedPaths = [] }
        adopt(finished)
        scanPhase = .finished
        guard fresh else { return }
        if environment.savesScanCache, case .path(let root)? = source { saveCache(finished, root: root) }
        startAnalysis()
    }

    /// Makes `new` the tree on screen. Selection and focus survive by path; analyses of the old tree are dropped.
    func adopt(_ new: FileTree) {
        cancelAnalyses()
        resetAnalyses()
        tree = new
        focus = nearestNode(to: focusPath, in: new)
        refreshSelection()
        scheduleLens()
    }

    // MARK: - Cache

    /// The age of the cached scan on screen, such as "3 days ago", or nil when the tree is a fresh scan.
    public var cachedScanAge: String? {
        guard isShowingCachedScan, let tree else { return nil }
        return Format.age(Int32(clamping: Int(tree.meta.scannedAt.timeIntervalSince1970)), now: now)
    }

    /// Where the scan of `root` is cached: under the data directory, never anywhere else.
    func cacheURL(forRoot root: String) -> URL {
        let label = (root as NSString).lastPathComponent.filter { $0.isLetter || $0.isNumber }
        let hash = root.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return environment.dataDirectory.appendingPathComponent("scans/\(label.isEmpty ? "root" : label)-\(String(hash, radix: 16)).dyscan")
    }

    /// Saves a finished scan on a background task.
    private func saveCache(_ tree: FileTree, root: String) {
        let url = cacheURL(forRoot: root)
        taskEpoch += 1
        saveTask = Task.detached(priority: .utility) { try? ScanCache.save(tree, to: url) }
    }

    // MARK: - Analyses

    /// Runs the post-scan chain: reclaim report, ownership, then kind refinement. Duplicates wait for `findDuplicates()`.
    func startAnalysis() {
        analysisToken?.cancel()
        guard let tree else { return }
        let token = CancelToken()
        analysisToken = token
        let (home, catalog, reader, minimum) = (environment.homePath, environment.appCatalog, environment.reader, environment.kindRefinementMinimumSize)
        analysis = [.reclaim: .running(fraction: nil), .ownership: .idle, .kinds: .idle, .duplicates: .idle]
        taskEpoch += 1
        analysisTask = Task { [weak self] in
            let first = await Task.detached(priority: .utility) { () -> (TreeLens, ReclaimReport?) in
                let lens = TreeLens(tree: tree)
                return (lens, ReclaimEngine.analyze(lens: lens, home: home, rules: ReclaimEngine.builtinRules, isCancelled: { token.isCancelled }))
            }.value
            let full = first.0
            guard let self, !token.isCancelled, let report = first.1 else { self?.markCancelled(token); return }
            self.reclaimReport = report
            self.analysis[.reclaim] = .done
            self.analysis[.ownership] = .running(fraction: nil)
            self.scheduleLens()

            let owners = await Task.detached(priority: .utility) {
                OwnershipEngine.analyze(lens: full, home: home, catalog: catalog, isCancelled: { token.isCancelled })
            }.value
            guard !token.isCancelled, let owners else { self.markCancelled(token); return }
            self.ownershipReport = owners
            self.analysis[.ownership] = .done
            self.analysis[.kinds] = .running(fraction: nil)
            self.scheduleWorklists()

            let refinement = await KindRefiner.refine(lens: full, reader: reader, minimumSize: minimum, isCancelled: { token.isCancelled })
            guard !token.isCancelled, let refinement, self.tree === tree else { self.markCancelled(token); return }
            self.kindRefinement = refinement
            let refined = tree.replacingKinds(refinement.kinds)
            if self.sqlResult?.tree === tree { self.sqlResult?.tree = refined }
            self.tree = refined
            self.analysis[.kinds] = .done
            self.scheduleLens()
        }
    }

    /// Marks running stages cancelled if `token` is the current chain's.
    private func markCancelled(_ token: CancelToken) {
        guard token.isCancelled else { return }
        for (stage, state) in analysis { if case .running = state, stage != .duplicates { analysis[stage] = .cancelled } }
    }

    /// Stops the post-scan chain and any duplicate search.
    public func cancelAnalyses() {
        analysisToken?.cancel()
        duplicatesToken?.cancel()
        for (stage, state) in analysis { if case .running = state { analysis[stage] = .cancelled } }
    }

    /// Searches for exact duplicates. Reads file contents, so it runs only when asked and can be cancelled.
    public func findDuplicates() {
        guard let tree, let lens = baseLens else { return }
        if case .running = analysis[.duplicates] { return }
        duplicatesToken?.cancel()
        let token = CancelToken()
        duplicatesToken = token
        analysis[.duplicates] = .running(fraction: 0)
        let (reader, minimum) = (environment.reader, environment.duplicateMinimumSize)
        taskEpoch += 1
        duplicatesTask = Task { [weak self] in
            let report = await DuplicateFinder.find(lens: lens, minimumSize: minimum, reader: reader, progress: { fraction in
                Task { @MainActor in
                    guard let self, case .running(let last?) = self.analysis[.duplicates], fraction - last >= 0.01 || fraction >= 1 else { return }
                    self.analysis[.duplicates] = .running(fraction: fraction)
                }
            }, isCancelled: { token.isCancelled })
            guard let self else { return }
            guard !token.isCancelled, self.tree?.count == tree.count else {
                if self.analysis[.duplicates] != .done { self.analysis[.duplicates] = .cancelled }
                return
            }
            self.duplicateReport = report
            self.analysis[.duplicates] = .done
            self.scheduleWorklists()
        }
    }

    /// Recomputes the worklists on a background task from the current reports, decisions and lens.
    func scheduleWorklists() {
        worklistToken?.cancel()
        guard let report = reclaimReport, let lens = baseLens, report.nodeTier.count == lens.tree.count else { return }
        let token = CancelToken()
        worklistToken = token
        let owners = ownershipReport ?? OwnershipReport(folders: [])
        let duplicates = duplicateReport
        let decisions = resolved?.effective ?? [UInt8](repeating: 0, count: lens.tree.count)
        let now = now
        taskEpoch += 1
        worklistTask = Task { [weak self] in
            let lists = await Task.detached(priority: .utility) {
                WorklistEngine.compute(lens: lens, report: report, ownership: owners, duplicates: duplicates, decisions: decisions, now: now)
            }.value
            guard let self, !token.isCancelled else { return }
            self.worklists = lists
        }
    }
}
