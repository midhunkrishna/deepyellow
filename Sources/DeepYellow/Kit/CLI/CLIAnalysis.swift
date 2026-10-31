import DYAdvisor
import DYAnalysis
import DYCore
import DYScan
import DYWorkspace
import Foundation

/// One row of the `things` output.
public struct ThingsRow: Equatable {
    public var path: String
    public var name: String
    public var bytes: UInt64
    public var files: UInt64
    /// "item" for a file or folder, "rest" for the smaller items rolled into a folder.
    public var kind: String
    public var items: Int?
}

/// The result of `things`.
public struct ThingsReport: Equatable {
    public var path: String
    public var total: UInt64
    public var thresholdBytes: UInt64
    public var rows: [ThingsRow]
}

/// One safety group of the `reclaim` output.
public struct ReclaimGroupRow: Equatable {
    public var id: String, title: String, tier: String
    public var bytes: UInt64, reclaimable: UInt64, files: UInt64
    public var items: Int
    public var cleanupCommand: String?
}

/// One worklist of the `reclaim` output.
public struct WorklistRow: Equatable {
    public var kind: String, title: String, why: String
    public var bytes: UInt64, files: UInt64
    public var items: Int
    public var top: [(path: String, bytes: UInt64)]

    public static func == (a: WorklistRow, b: WorklistRow) -> Bool {
        a.kind == b.kind && a.title == b.title && a.why == b.why && a.bytes == b.bytes && a.files == b.files
            && a.items == b.items && a.top.map(\.path) == b.top.map(\.path)
    }
}

/// The result of `reclaim`.
public struct ReclaimSummary: Equatable {
    public var path: String
    public var total: UInt64
    public var groups: [ReclaimGroupRow]
    public var worklists: [WorklistRow]
}

/// The result of `spectrum`.
public struct SpectrumSummary {
    public var path: String
    public var totalFiles: UInt64
    public var totalBytes: UInt64
    public var filesHolding80PercentOfBytes: Int
    public var bins: [(lower: UInt64, upper: UInt64, files: UInt64, bytes: UInt64)]
}

/// One set of identical files in the `dupes` output.
public struct DuplicateRow {
    public var size: UInt64
    public var paths: [String]
    public var wasted: UInt64
}

/// The result of `dupes`.
public struct DuplicateSummary {
    public var path: String
    public var bytesHashed: UInt64
    public var sets: [DuplicateRow]
    public var wasted: UInt64 { sets.reduce(0) { $0 + $1.wasted } }
}

/// Runs the analysis engines over a tree and shapes the results for printing. Pure with respect to the disk
/// except for `duplicates`, which reads file contents through the supplied reader.
public enum CLIAnalysis {
    /// Ranked things under the tree root. Without `minimumBytes` the threshold gives about `top ?? 25` rows.
    public static func things(tree: FileTree, minimumBytes: UInt64?, top: Int?) -> ThingsReport {
        let lens = TreeLens(tree: tree)
        let threshold = minimumBytes ?? ThingsEngine.thresholdForApproximately(items: top ?? 25, lens: lens, under: 0, metric: .bytes)
        let result = ThingsEngine.cut(lens: lens, under: 0, threshold: threshold, metric: .bytes)
        var rows = result.items.map { thing -> ThingsRow in
            switch thing.content {
            case .node(let node):
                return ThingsRow(path: tree.path(node), name: tree.name(node), bytes: thing.value, files: thing.files, kind: "item", items: nil)
            case .rest(let parent, let items):
                return ThingsRow(path: tree.path(parent), name: tree.name(parent), bytes: thing.value, files: thing.files, kind: "rest", items: items)
            }
        }
        if let top { rows = Array(rows.prefix(top)) }
        return ThingsReport(path: tree.meta.rootPath, total: result.total, thresholdBytes: threshold, rows: rows)
    }

    /// Safety groups and worklists, using `home` to anchor the home-relative rules.
    public static func reclaim(tree: FileTree, home: String, catalog: AppCatalog) -> ReclaimSummary {
        let lens = TreeLens(tree: tree)
        let report = ReclaimEngine.analyze(lens: lens, home: home, rules: ReclaimEngine.builtinRules, isCancelled: { false })
        let ownership = OwnershipEngine.analyze(lens: lens, home: home, catalog: catalog, isCancelled: { false })
        let groups = (report?.families ?? []).map { family in
            ReclaimGroupRow(id: family.rule.id, title: family.rule.title, tier: String(describing: family.rule.tier), bytes: family.bytes,
                            reclaimable: family.reclaimable, files: family.files, items: family.nodes.count,
                            cleanupCommand: family.rule.cleanupCommand)
        }
        var lists: [Worklist] = []
        if let report, let ownership {
            lists = WorklistEngine.compute(lens: lens, report: report, ownership: ownership, duplicates: nil,
                                           decisions: [UInt8](repeating: 0, count: tree.count), now: Int32(Date().timeIntervalSince1970))
        }
        let rows = lists.filter { $0.kind != .duplicates }.map { list in
            WorklistRow(kind: kindName(list.kind), title: list.title, why: list.why, bytes: list.bytes, files: list.files, items: list.nodes.count,
                        top: list.nodes.prefix(5).map { (tree.path($0), lens.value($0, .bytes)) })
        }
        return ReclaimSummary(path: tree.meta.rootPath, total: tree.allocated(0), groups: groups, worklists: rows)
    }

    /// The stable name of a worklist kind.
    static func kindName(_ kind: WorklistKind) -> String {
        switch kind {
        case .forgotten: "forgotten"
        case .duplicates: "duplicates"
        case .leftovers: "leftovers"
        case .largestUndecided: "largestUndecided"
        }
    }

    /// The size histogram and the Pareto figure.
    public static func spectrum(tree: FileTree) -> SpectrumSummary {
        let result = SpectrumEngine.compute(lens: TreeLens(tree: tree), under: 0)
        return SpectrumSummary(path: tree.meta.rootPath, totalFiles: result.totalFiles, totalBytes: result.totalBytes,
                               filesHolding80PercentOfBytes: result.itemsForShare(0.8),
                               bins: result.bins.map { ($0.lower, $0.upper, $0.count, $0.bytes) })
    }

    /// Exact duplicate sets of files at least `minimumBytes` large, biggest waste first.
    public static func duplicates(tree: FileTree, minimumBytes: UInt64, reader: FileReading,
                                  progress: @escaping @Sendable (Double) -> Void) async -> DuplicateSummary {
        let report = await DuplicateFinder.find(lens: TreeLens(tree: tree), minimumSize: minimumBytes, reader: reader,
                                                progress: progress, isCancelled: { false })
        let sets = report.sets.map { DuplicateRow(size: $0.size, paths: $0.nodes.map { tree.path($0) }, wasted: $0.wastedBytes) }
        return DuplicateSummary(path: tree.meta.rootPath, bytesHashed: report.bytesHashed, sets: sets)
    }
}

/// Scans a folder to completion for the CLI, blocking the calling thread.
public enum CLIScan {
    /// Scans `path`. `progress` receives a file count about four times a second.
    public static func scan(path: String, progress: (@Sendable (ScanProgress) -> Void)?) -> FileTree {
        let box = ResultBox<FileTree>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let scanner = DiskScanner(options: ScanOptions(root: path))
            for await event in scanner.start() {
                switch event {
                case .progress(let value): progress?(value)
                case .finished(let tree): box.value = tree
                case .snapshot: break
                }
            }
            done.signal()
        }
        done.wait()
        return box.value ?? FileTree(columns: FileTreeColumns(), meta: ScanMeta(rootPath: path))
    }

    /// Runs async work to completion on the calling thread.
    public static func blocking<T>(_ work: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await work()
            done.signal()
        }
        done.wait()
        return box.value!
    }
}

/// A one-slot result holder shared between a task and the thread waiting for it.
final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
