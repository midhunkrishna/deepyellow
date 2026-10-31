import DYAdvisor
import DYAnalysis
import DYCore
import DYDecide
import DYPreview
import DYScan
import DYSQL
import Foundation
import Observation

/// Where the workspace gets its disk.
public enum WorkspaceSource: Equatable, Sendable {
    /// The sample disk. Needs an environment with a sample disk, such as `WorkspaceEnvironment.demo`.
    case demo
    /// A folder or volume to scan.
    case path(String)
}

/// How far the scan has got.
public enum ScanPhase: Equatable, Sendable {
    case idle, loadingCache, scanning, finished
}

/// The seven lenses, in key order `1` to `7`.
public enum LensKind: String, CaseIterable, Sendable {
    case map, things, spectrum, field, rings, browse, reclaim
}

/// The slow, cancellable analyses that run after a scan.
public enum AnalysisStage: String, CaseIterable, Sendable {
    case reclaim, ownership, kinds, duplicates
}

/// What one analysis is doing. `fraction` is nil when the stage can't say how far along it is.
public enum StageState: Equatable, Sendable {
    case idle
    case running(fraction: Double?)
    case done
    case cancelled
}

/// Where the SQL drawer's last run stands.
public enum SQLPhase: Equatable {
    case idle, running, finished
    case failed(SQLFailure)
}

/// A short message for the toast line, optionally with an undo.
public struct Notice: Identifiable, Equatable, Sendable {
    public var id: Int
    public var message: String
    public var canUndo: Bool
}

/// The headless model every view binds to. Holds no views and no GPU state.
///
/// Heavy work (ignore rules, query, decisions, Trash state, analyses, view results) runs on background tasks that are
/// cancelled when newer input arrives, and only the newest result is published. Hover and selection never recompute anything
/// heavy. Call `settle()` to wait for all background work.
@MainActor @Observable
public final class Workspace {
    @ObservationIgnored public let environment: WorkspaceEnvironment
    @ObservationIgnored let decisionStore: DecisionStore
    @ObservationIgnored let executor: TrashExecutor

    // MARK: Source and scan

    public internal(set) var source: WorkspaceSource?
    /// The tree being shown: a cached scan, a live snapshot or the finished scan.
    public internal(set) var tree: FileTree?
    public internal(set) var scanPhase: ScanPhase = .idle
    public internal(set) var scanProgress: ScanProgress?
    /// True while the tree is a partial snapshot of a running scan.
    public internal(set) var isLiveSnapshot = false
    /// True while the tree on screen comes from the cache and a fresh scan hasn't finished yet.
    public internal(set) var isShowingCachedScan = false
    public internal(set) var scanWasCancelled = false
    public internal(set) var volumes: [VolumeInfo] = []

    // MARK: Lens and view options

    /// The tree seen through ignore rules, the query and Trash state.
    public internal(set) var lens: TreeLens?
    /// The same without the query: what the ledger and worklists measure.
    public internal(set) var baseLens: TreeLens?
    public internal(set) var ignoreResult: IgnoreResult?
    public internal(set) var resolved: ResolvedDecisions?
    public internal(set) var dominantKinds: [UInt8] = []
    /// True while a newer lens is being computed. Views keep drawing the previous one.
    public internal(set) var isRecomputing = false
    public internal(set) var queryText = ""
    public internal(set) var query = Query.parse("")
    public internal(set) var ignoreRules: IgnoreRuleSet
    public internal(set) var decisionVersion = 0
    public internal(set) var lensKind: LensKind = .map
    public internal(set) var metric: Metric = .bytes
    public internal(set) var colorMode: ColorMode = .kind
    public internal(set) var fieldClock: FieldClock = .modified
    public internal(set) var focus: NodeID = 0
    /// The node under the pointer. Setting it costs nothing.
    public var hover: NodeID?

    // MARK: Selection

    public internal(set) var selectionPaths: Set<String> = []
    /// The selected paths that exist in the current tree, ascending.
    public internal(set) var selectedNodes: [NodeID] = []
    public internal(set) var selectionCount = 0
    /// Bytes under the selection, counting each byte once even when a folder and its contents are both selected.
    public internal(set) var selectionBytes: UInt64 = 0
    /// The path last clicked, which the preview shows.
    public internal(set) var primarySelectionPath: String?

    // MARK: Analyses

    public internal(set) var analysis: [AnalysisStage: StageState] = [:]
    public internal(set) var reclaimReport: ReclaimReport?
    public internal(set) var ownershipReport: OwnershipReport?
    public internal(set) var kindRefinement: KindRefinement?
    public internal(set) var duplicateReport: DuplicateReport?
    public internal(set) var worklists: [Worklist] = []
    public internal(set) var things: ThingsResult?
    /// The cut size, in the current metric, that produced `things`.
    public internal(set) var thingsThreshold: UInt64?
    public internal(set) var thingsItemTarget = 48
    public internal(set) var spectrum: SpectrumResult?
    public internal(set) var field: FieldData?

    // MARK: Plan and Trash

    /// The plan for the current decisions. Refined by measurement once `planIsRefined` is true.
    public internal(set) var plan: RemovalPlan?
    public internal(set) var planIsRefined = false
    public internal(set) var isApplying = false
    public internal(set) var applyProgress: Double?
    public internal(set) var lastExecution: ExecutionReport?
    public internal(set) var canUndoApply = false
    /// Paths moved to the Trash in this session and not restored.
    public internal(set) var trashedPaths: Set<String> = []

    // MARK: Review and messages

    public internal(set) var review: ReviewSession?
    public internal(set) var notice: Notice?

    // MARK: SQL

    /// The text of the last run requested.
    public internal(set) var sqlText = ""
    public internal(set) var sqlPhase: SQLPhase = .idle
    public internal(set) var sqlResult: SQLResult?
    /// The group row narrowing the views, if any.
    public internal(set) var sqlDrillRow: Int?
    /// Topmost nodes of the set narrowing the views, as of the last published lens.
    public internal(set) var sqlRootCount = 0
    var sqlHistoryEntries: [String] = []

    // MARK: Background bookkeeping

    @ObservationIgnored var sqlTask: Task<Void, Never>?
    @ObservationIgnored var sqlToken: CancelToken?
    @ObservationIgnored var sqlBasis: SQLBasis?
    @ObservationIgnored var sqlDeferred = false

    @ObservationIgnored var taskEpoch = 0
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var scanCancel: (@Sendable () -> Void)?
    @ObservationIgnored var lensTask: Task<Void, Never>?
    @ObservationIgnored var lensToken: CancelToken?
    @ObservationIgnored var viewTask: Task<Void, Never>?
    @ObservationIgnored var viewToken: CancelToken?
    @ObservationIgnored var analysisTask: Task<Void, Never>?
    @ObservationIgnored var analysisToken: CancelToken?
    @ObservationIgnored var duplicatesTask: Task<Void, Never>?
    @ObservationIgnored var duplicatesToken: CancelToken?
    @ObservationIgnored var worklistTask: Task<Void, Never>?
    @ObservationIgnored var worklistToken: CancelToken?
    @ObservationIgnored var refineTask: Task<Void, Never>?
    @ObservationIgnored var refineToken: CancelToken?
    @ObservationIgnored var applyToken: CancelToken?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var cachedIgnore: CachedIgnore?
    @ObservationIgnored var rulesRevision = 0
    @ObservationIgnored var noticeUndo: (@MainActor () -> Void)?
    @ObservationIgnored var noticeCounter = 0
    @ObservationIgnored var applyClearedVersion: Int?
    @ObservationIgnored var focusPath = "/"

    /// Creates a workspace. Nothing is scanned until `open(_:)`.
    public init(environment: WorkspaceEnvironment) {
        self.environment = environment
        let directory = environment.dataDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        decisionStore = DecisionStore(fileURL: directory.appendingPathComponent("decisions.json"))
        executor = TrashExecutor(mover: environment.mover,
                                 journalURL: environment.keepsTrashJournal ? directory.appendingPathComponent("trash-journal.json") : nil)
        ignoreRules = Workspace.loadRules(directory)
        volumes = environment.volumes()
        canUndoApply = executor.canUndo
        sqlHistoryEntries = Workspace.loadSQLHistory(directory)
    }

    /// The reference time for ages, in seconds since 1970.
    var now: Int32 { Int32(clamping: Int(environment.clock().timeIntervalSince1970)) }

    // MARK: - View options

    /// Switches lens. Focus, selection and query stay.
    public func setLens(_ kind: LensKind) {
        lensKind = kind
        scheduleViewResults()
    }

    /// Switches between bytes and file count.
    public func setMetric(_ value: Metric) {
        metric = value
        scheduleViewResults()
    }

    /// Chooses what tile colour encodes. Directory dominant kinds are computed only for `.kind`.
    public func setColorMode(_ mode: ColorMode) {
        let needsKinds = mode == .kind && dominantKinds.isEmpty
        colorMode = mode
        if needsKinds { scheduleLens() }
    }

    /// Chooses which clock the Field plots.
    public func setFieldClock(_ clock: FieldClock) {
        fieldClock = clock
        scheduleViewResults()
    }

    /// Sets how many things the Things list should roughly show.
    public func setThingsItemTarget(_ items: Int) {
        thingsItemTarget = max(1, items)
        scheduleViewResults()
    }

    /// Writes the query. Parsing is immediate; the lens follows on a background task.
    public func setQuery(_ text: String) {
        queryText = text
        query = Query.parse(text)
        scheduleLens()
    }

    /// The per-node visual state for renderers.
    public var nodeStyle: NodeStyle {
        NodeStyle(colorMode: colorMode, decisions: resolved?.effective ?? [], safety: reclaimReport?.nodeTier ?? [],
                  dominantKind: colorMode == .kind ? dominantKinds : [], now: now)
    }

    // MARK: - Focus

    /// Zooms to a node. The focus survives rescans by path.
    public func setFocus(_ node: NodeID) {
        guard let tree, node >= 0, Int(node) < tree.count else { return }
        focus = node
        focusPath = tree.path(node)
        scheduleViewResults()
    }

    /// Zooms into a directory, ignoring files.
    public func zoomIn(_ node: NodeID) {
        guard let tree, node >= 0, Int(node) < tree.count, tree.isDirectory(node) else { return }
        setFocus(node)
    }

    /// Zooms out one level. Returns false at the root.
    @discardableResult
    public func zoomOut() -> Bool {
        guard let tree, focus > 0 else { return false }
        setFocus(tree.parent(focus))
        return true
    }

    /// Nodes from the root to the focus, for the breadcrumb.
    public var breadcrumb: [NodeID] { tree?.ancestry(focus) ?? [] }

    /// Finds the node at `path`, or its nearest ancestor that exists.
    func nearestNode(to path: String, in tree: FileTree) -> NodeID {
        var candidate = path
        while true {
            if let node = tree.find(path: candidate) { return node }
            let parent = (candidate as NSString).deletingLastPathComponent
            if parent == candidate || parent.isEmpty { return 0 }
            candidate = parent
        }
    }

    // MARK: - Lens recomputation

    /// Recomputes ignore rules, decisions, query, Trash state and the plan on a background task.
    ///
    /// An older run is cancelled, and only the newest result is published.
    func scheduleLens() {
        lensToken?.cancel()
        guard let tree else {
            lens = nil
            baseLens = nil
            isRecomputing = false
            return
        }
        let token = CancelToken()
        lensToken = token
        isRecomputing = true
        let input = LensInput(tree: tree, rules: ignoreRules, rulesRevision: rulesRevision, home: environment.homePath, query: query,
                              store: decisionStore, nodeTier: reclaimReport?.nodeTier, trashed: trashedPaths, now: now,
                              wantsDominantKinds: colorMode == .kind, cachedIgnore: cachedIgnore, sqlNodes: sqlActiveNodes)
        taskEpoch += 1
        lensTask = Task { [weak self] in
            let bundle = await Task.detached(priority: .userInitiated) { LensPipeline.build(input, isCancelled: { token.isCancelled }) }.value
            guard let self, let bundle, !token.isCancelled else { return }
            self.publish(bundle)
        }
    }

    /// Publishes a finished bundle, unless the tree has moved on.
    func publish(_ bundle: LensBundle) {
        guard bundle.tree === tree else { return }
        cachedIgnore = CachedIgnore(tree: bundle.tree, rulesRevision: bundle.rulesRevision, result: bundle.ignore)
        lens = bundle.lens
        baseLens = bundle.baseLens
        ignoreResult = bundle.ignore
        resolved = bundle.resolved
        dominantKinds = bundle.dominantKinds
        plan = bundle.plan
        planIsRefined = false
        isRecomputing = false
        sqlRootCount = bundle.sqlRoots
        refreshSelection()
        scheduleViewResults()
        scheduleWorklists()
        scheduleRefine()
        continueSQL()
    }

    /// Computes the active lens's result (Things, Spectrum or Field) on a background task.
    func scheduleViewResults() {
        viewToken?.cancel()
        guard let lens, let tree, focus >= 0, Int(focus) < tree.count else { return }
        let kind = lensKind
        guard kind == .things || kind == .spectrum || kind == .field else { return }
        let token = CancelToken()
        viewToken = token
        let (under, metric, clock, target) = (focus, metric, fieldClock, thingsItemTarget)
        taskEpoch += 1
        viewTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> (ThingsResult?, UInt64?, SpectrumResult?, FieldData?) in
                switch kind {
                case .things:
                    let threshold = ThingsEngine.thresholdForApproximately(items: target, lens: lens, under: under, metric: metric)
                    return (ThingsEngine.cut(lens: lens, under: under, threshold: threshold, metric: metric), threshold, nil, nil)
                case .spectrum: return (nil, nil, SpectrumEngine.compute(lens: lens, under: under), nil)
                default: return (nil, nil, nil, FieldEngine.compute(lens: lens, under: under, clock: clock, maxPoints: 150_000))
                }
            }.value
            guard let self, !token.isCancelled else { return }
            switch kind {
            case .things: (self.things, self.thingsThreshold) = (result.0, result.1)
            case .spectrum: self.spectrum = result.2
            default: self.field = result.3
            }
        }
    }

    // MARK: - Waiting and messages

    /// Waits until every background task has finished and nothing newer was queued meanwhile.
    public func settle() async {
        while true {
            let epoch = taskEpoch
            let tasks = [scanTask, lensTask, viewTask, analysisTask, duplicatesTask, worklistTask, refineTask, saveTask, sqlTask].compactMap { $0 }
            for task in tasks { await task.value }
            if epoch == taskEpoch { return }
        }
    }

    /// Shows a message, with an optional undo action.
    func post(_ message: String, undo: (@MainActor () -> Void)? = nil) {
        noticeCounter += 1
        notice = Notice(id: noticeCounter, message: message, canUndo: undo != nil)
        noticeUndo = undo
    }

    /// Runs the shown message's undo, if it has one, and clears the message.
    public func undoNotice() {
        let action = noticeUndo
        notice = nil
        noticeUndo = nil
        action?()
    }

    /// Clears the shown message.
    public func dismissNotice() {
        notice = nil
        noticeUndo = nil
    }
}
