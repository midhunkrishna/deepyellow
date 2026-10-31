import DYCore
import DYSQL
import Foundation

/// The state a SQL result was computed from. When it changes, the result is stale and runs again.
struct SQLBasis: Equatable {
    var tree: ObjectIdentifier
    var rules: Int
    var decisions: Int
    var trashed: Set<String>
    var hasTiers: Bool
}

/// SQL results as a set of things on disk: every view shows the set, through the same path as the `/` query.
///
/// SQL only reads. It never marks anything, never builds a plan and never calls the Trash mover.
extension Workspace {
    /// Most entries kept in the history.
    static let sqlHistoryLimit = 20

    // MARK: - Running

    /// Runs a statement on a background task. A newer run cancels an older one, and a failure leaves the previous filter in place.
    ///
    /// Available once the scan has finished. Before that the phase becomes `failed`.
    public func runSQL(_ text: String) {
        sqlText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sqlPhase = .failed(.invalid(message: "Type a query first."))
            return
        }
        recordSQLHistory(trimmed)
        guard tree != nil, scanPhase == .finished, !isLiveSnapshot else {
            sqlToken?.cancel()
            sqlPhase = .failed(.invalid(message: "SQL is available when the scan finishes."))
            return
        }
        sqlDrillRow = nil
        beginSQL()
    }

    /// Stops a running statement. A result already on screen stays.
    public func cancelSQL() {
        sqlToken?.cancel()
        sqlDeferred = false
        if sqlPhase == .running { sqlPhase = sqlResult == nil ? .idle : .finished }
    }

    /// Returns the views to normal. The text and the history stay.
    public func clearSQL() {
        let wasFiltering = sqlIsFiltering
        cancelSQL()
        sqlResult = nil
        sqlDrillRow = nil
        sqlPhase = .idle
        if wasFiltering { scheduleLens() }
    }

    /// Narrows the views to one group of a `.groups` result, or back to every group with nil. Other rows and shapes are ignored.
    public func drillSQL(row: Int?) {
        guard let result = sqlResult, result.shape == .groups else { return }
        if let row, !result.rowGroup.indices.contains(row) { return }
        guard row != sqlDrillRow else { return }
        sqlDrillRow = row
        scheduleLens()
    }

    /// Selects every node of the current set.
    public func selectSQLResults() {
        guard let nodes = sqlActiveNodes else { return }
        select(nodes)
    }

    /// Reviews every node of the current set.
    public func reviewSQLResults() {
        guard let nodes = sqlActiveNodes else { return }
        startReview(nodes: nodes, title: "SQL results")
    }

    // MARK: - The set

    /// The nodes narrowing the views, or nil when nothing does. A set never applies to a tree its ids don't belong to.
    var sqlActiveNodes: [NodeID]? {
        guard let result = sqlResult, result.shape != .tableOnly, result.tree === tree else { return nil }
        if result.shape == .groups, let row = sqlDrillRow, result.rowGroup.indices.contains(row) { return result.rowGroup[row] }
        return result.nodes
    }

    /// True when a result is narrowing the views now.
    public var sqlIsFiltering: Bool { sqlActiveNodes != nil }

    /// "12 things · 184 GB" from the lens, or nil when not filtering.
    public var sqlFilterSummary: String? {
        guard let nodes = sqlActiveNodes, let lens else { return nil }
        return "\(Format.count(nodes.count)) \(nodes.count == 1 ? "thing" : "things") · \(Format.bytes(lens.size.first ?? 0))"
    }

    // MARK: - History

    /// The statements run, newest first, at most 20. Saved as `sql-history.json` in the data directory.
    public var sqlHistory: [String] { sqlHistoryEntries }

    /// Moves a statement to the front of the history, without duplicates, and saves.
    private func recordSQLHistory(_ text: String) {
        sqlHistoryEntries.removeAll { $0 == text }
        sqlHistoryEntries.insert(text, at: 0)
        if sqlHistoryEntries.count > Self.sqlHistoryLimit { sqlHistoryEntries.removeLast(sqlHistoryEntries.count - Self.sqlHistoryLimit) }
        guard let data = try? JSONEncoder().encode(sqlHistoryEntries) else { return }
        try? data.write(to: environment.dataDirectory.appendingPathComponent("sql-history.json"), options: .atomic)
    }

    /// Reads the saved history, or an empty one.
    static func loadSQLHistory(_ directory: URL) -> [String] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("sql-history.json")),
              let entries = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(entries.prefix(sqlHistoryLimit))
    }

    // MARK: - Background run

    /// What the current state would hand to a query. Compared with the basis of the last run to see whether it is stale.
    private func currentSQLBasis(_ tree: FileTree) -> SQLBasis {
        SQLBasis(tree: ObjectIdentifier(tree), rules: rulesRevision, decisions: decisionVersion, trashed: trashedPaths,
                 hasTiers: reclaimReport != nil)
    }

    /// Starts the statement in `sqlText` on the published lens, cancelling any older run.
    ///
    /// While a lens is being recomputed the run waits for it, so a query always reads the rules, marks and Trash state on screen.
    func beginSQL() {
        sqlToken?.cancel()
        guard let tree, let baseLens, scanPhase == .finished, !isLiveSnapshot else { return }
        sqlPhase = .running
        guard !isRecomputing else {
            sqlDeferred = true
            return
        }
        sqlDeferred = false
        let token = CancelToken()
        sqlToken = token
        sqlBasis = currentSQLBasis(tree)
        let tiers = reclaimReport.map(\.nodeTier).flatMap { $0.count == tree.count ? $0 : nil } ?? []
        let context = SQLContext(tree: tree, lens: baseLens, decisions: resolved?.effective ?? [], safety: tiers, now: now)
        let (text, previousRows, drill) = (sqlText, sqlResult?.rowCount, sqlDrillRow)
        taskEpoch += 1
        sqlTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<SQLResult, SQLFailure> in
                do {
                    return .success(try SQLEngine.run(text, context: context, isCancelled: { token.isCancelled }))
                } catch let failure as SQLFailure {
                    return .failure(failure)
                } catch {
                    return .failure(.invalid(message: "\(error)"))
                }
            }.value
            guard let self, !token.isCancelled else { return }
            self.finishSQL(outcome, tree: tree, previousRows: previousRows, drill: drill)
        }
    }

    /// Takes a finished run. A result for a tree that has since been replaced is dropped, because the re-run follows the new lens.
    private func finishSQL(_ outcome: Result<SQLResult, SQLFailure>, tree: FileTree, previousRows: Int?, drill: Int?) {
        switch outcome {
        case .success(let result):
            guard self.tree === tree else { return }
            sqlResult = result
            sqlDrillRow = (result.shape == .groups && previousRows == result.rowCount && drill.map { result.rowGroup.indices.contains($0) } == true) ? drill : nil
            sqlPhase = .finished
            scheduleLens()
        case .failure(.cancelled):
            sqlPhase = sqlResult == nil ? .idle : .finished
        case .failure(let failure):
            sqlPhase = .failed(failure)
        }
    }

    /// After a lens is published: starts a waiting run, or re-runs a result whose inputs have changed.
    func continueSQL() {
        if sqlDeferred { beginSQL(); return }
        guard let tree, sqlResult != nil || sqlPhase == .running, !sqlText.isEmpty else { return }
        if sqlBasis != currentSQLBasis(tree) { beginSQL() }
    }

    /// Forgets the result when a new source is opened. The text and the history stay.
    func resetSQL() {
        sqlToken?.cancel()
        sqlDeferred = false
        sqlResult = nil
        sqlDrillRow = nil
        sqlBasis = nil
        sqlPhase = .idle
    }
}
