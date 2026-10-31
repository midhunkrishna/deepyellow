import DYAdvisor
import DYAnalysis
import DYCore
import DYDecide
import Foundation

/// Marks, undo and redo, and the ignore rules. Marks apply to the selection or to the review item, never to anything else.
extension Workspace {
    // MARK: - Marks

    /// Marks the selection, or the current review item while reviewing, as `decision`.
    ///
    /// With nothing selected and no review, nothing is marked and a message says so. Returns whether anything was marked.
    @discardableResult
    public func mark(_ decision: Decision) -> Bool {
        if review != nil { return reviewVerdict(decision) }
        let paths = selectionPaths.sorted()
        guard !paths.isEmpty else {
            post("Select something first. Nothing is ever marked on its own.")
            return false
        }
        return record(decision, paths: paths)
    }

    /// Selects every node of a Reclaim family or worklist so the user sees what is about to be marked, then marks it.
    @discardableResult
    public func mark(_ decision: Decision, nodes: [NodeID]) -> Bool {
        select(nodes)
        return mark(decision)
    }

    /// Stores the verdict and recomputes the lens in the background.
    private func record(_ decision: Decision, paths: [String]) -> Bool {
        guard let tree else { return false }
        decisionStore.set(decision, paths: paths, tree: tree)
        decisionVersion = decisionStore.version
        scheduleLens()
        return true
    }

    /// Undoes the last mark. While reviewing, the review steps back to that item too.
    @discardableResult
    public func undoDecision() -> Bool {
        guard decisionStore.undo() else { return false }
        decisionVersion = decisionStore.version
        if var session = review, session.stepBack() != nil { review = session }
        scheduleLens()
        return true
    }

    /// Redoes the last undone mark.
    @discardableResult
    public func redoDecision() -> Bool {
        guard decisionStore.redo() else { return false }
        decisionVersion = decisionStore.version
        scheduleLens()
        return true
    }

    // MARK: - Ignore rules

    /// What a "Hide" command matches.
    public enum HideTarget: Sendable {
        /// This exact path.
        case path
        /// Everything with this name.
        case name
        /// Every file with this extension.
        case ext
    }

    /// Hides nodes with a new rule. Hidden is never gone: the ledger still counts it. The message offers undo.
    public func hide(_ target: HideTarget, nodes: [NodeID]) {
        guard let tree, let first = nodes.first, first >= 0, Int(first) < tree.count else { return }
        let name = tree.name(first)
        let ext = (name as NSString).pathExtension
        let (pattern, label): (String, String)
        switch target {
        case .path: (pattern, label) = (tree.path(first), "Hidden by you: \(name)")
        case .name: (pattern, label) = (name, "Hidden by you: everything named \(name)")
        case .ext:
            guard !ext.isEmpty else { post("This item has no extension."); return }
            (pattern, label) = ("*.\(ext)", "Hidden by you: all .\(ext) files")
        }
        let previous = ignoreRules
        guard !previous.rules.contains(where: { $0.pattern == pattern }) else { return }
        var rules = previous
        rules.rules.append(IgnoreRule(pattern: pattern, label: label))
        setRules(rules)
        clearSelection()
        post("\(label). Still counted in the ledger.") { [weak self] in self?.setRules(previous) }
    }

    /// Turns a rule on or off.
    public func setRule(_ id: UUID, enabled: Bool) {
        var rules = ignoreRules
        guard let index = rules.rules.firstIndex(where: { $0.id == id }) else { return }
        rules.rules[index].enabled = enabled
        setRules(rules)
    }

    /// Deletes a rule you added. Built-in rules can only be turned off.
    public func deleteRule(_ id: UUID) {
        var rules = ignoreRules
        rules.rules.removeAll { $0.id == id && !$0.isPreset }
        setRules(rules)
    }

    /// Replaces the rules, saves them and recomputes the lens.
    func setRules(_ rules: IgnoreRuleSet) {
        ignoreRules = rules
        rulesRevision += 1
        Workspace.saveRules(rules, to: environment.dataDirectory)
        scheduleLens()
    }

    /// Reads the saved rules, or the defaults when there are none.
    static func loadRules(_ directory: URL) -> IgnoreRuleSet {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("ignore-rules.json")),
              let rules = try? JSONDecoder().decode(IgnoreRuleSet.self, from: data) else { return .defaults }
        return rules
    }

    /// Writes the rules atomically.
    static func saveRules(_ rules: IgnoreRuleSet, to directory: URL) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: directory.appendingPathComponent("ignore-rules.json"), options: .atomic)
    }

    // MARK: - Review

    /// Starts reviewing nodes. Returns false when there is nothing to review.
    @discardableResult
    public func startReview(nodes: [NodeID], title: String) -> Bool {
        guard let tree else { return false }
        let items: [ReviewItem] = nodes.filter { $0 >= 0 && Int($0) < tree.count }.map { node in
            ReviewItem(path: tree.path(node), name: tree.name(node), bytes: lens?.size[Int(node)] ?? tree.allocated(node),
                       kind: tree.kind(node), isDirectory: tree.isDirectory(node))
        }
        guard !items.isEmpty else {
            post("Nothing to review here.")
            return false
        }
        review = ReviewSession(title: title, items: items)
        return true
    }

    /// Reviews the selection, or the largest undecided files under the focus when nothing is selected.
    @discardableResult
    public func startReview() async -> Bool {
        if !selectedNodes.isEmpty { return startReview(nodes: selectedNodes, title: "Selected items") }
        guard let lens, let resolved, let tiers = reclaimReport?.nodeTier else {
            return startReview(nodes: [], title: "")
        }
        let (under, effective) = (focus, resolved.effective)
        let nodes = await Task.detached { Self.largestUndecided(lens: lens, under: under, effective: effective, tiers: tiers, limit: 18) }.value
        return startReview(nodes: nodes, title: "Largest undecided files")
    }

    /// Reviews a Reclaim family.
    @discardableResult
    public func startReview(family: ReclaimFamily) -> Bool { startReview(nodes: family.nodes, title: family.rule.title) }

    /// Reviews a worklist.
    @discardableResult
    public func startReview(worklist: Worklist) -> Bool { startReview(nodes: worklist.nodes, title: worklist.title) }

    /// Gives the current review item a verdict and moves to the next. The verdict is staged like any other mark.
    @discardableResult
    public func reviewVerdict(_ decision: Decision) -> Bool {
        guard var session = review, let path = session.record(decision) else { return false }
        review = session
        return record(decision, paths: [path])
    }

    /// Jumps to an item in the strip without giving a verdict.
    public func reviewGo(to position: Int) {
        guard var session = review else { return }
        session.go(to: position)
        review = session
    }

    /// Leaves the review. Verdicts already given stay staged.
    public func endReview() { review = nil }

    /// The biggest files under `under` that have no decision and are not `never`, largest first.
    nonisolated static func largestUndecided(lens: TreeLens, under: NodeID, effective: [UInt8], tiers: [UInt8], limit: Int) -> [NodeID] {
        let tree = lens.tree
        var found: [NodeID] = []
        var stack = [under]
        while let node = stack.popLast() {
            let index = Int(node)
            guard lens.included[index] else { continue }
            if tree.isDirectory(node) {
                stack.append(contentsOf: tree.children(node))
            } else if lens.size[index] > 0, effective[index] == 0, tiers[index] != SafetyTier.never.rawValue {
                found.append(node)
                if found.count > limit * 8 { found = trimmed(found, lens: lens, limit: limit) }
            }
        }
        return trimmed(found, lens: lens, limit: limit)
    }

    /// The `limit` largest of `nodes`.
    nonisolated private static func trimmed(_ nodes: [NodeID], lens: TreeLens, limit: Int) -> [NodeID] {
        Array(nodes.sorted { lens.size[Int($0)] != lens.size[Int($1)] ? lens.size[Int($0)] > lens.size[Int($1)] : $0 < $1 }.prefix(limit))
    }

    // MARK: - Plan and Trash

    /// Whether Apply is allowed right now. Needs the safety advice, because the planner uses it to block `never` items.
    public var canApply: Bool {
        guard let plan, let tree, let report = reclaimReport else { return false }
        return !plan.items.isEmpty && !isApplying && !isRecomputing && report.nodeTier.count == tree.count
    }

    /// Bytes staged for removal, as the plan sees them.
    public var stagedBytes: UInt64 { plan?.totalBytes ?? 0 }

    /// The plan's estimate in words. "frees at least" only when the figure is a floor.
    public var planEstimateText: String {
        guard let plan, !plan.items.isEmpty else { return "Nothing staged" }
        let verb = plan.estimateIsLowerBound ? "frees at least" : "frees"
        return "\(verb) \(Format.bytes(plan.totalReclaimable)) once the Trash is emptied"
    }

    /// Refines the plan's figures with measured private bytes on a background task.
    func scheduleRefine() {
        refineToken?.cancel()
        guard let current = plan, !current.items.isEmpty else {
            planIsRefined = true
            return
        }
        let token = CancelToken()
        refineToken = token
        let probe = environment.probe
        taskEpoch += 1
        refineTask = Task { [weak self] in
            let refined = await RemovalPlanner.refine(current, probe: probe, isCancelled: { token.isCancelled })
            guard let self, !token.isCancelled else { return }
            self.plan = refined
            self.planIsRefined = true
        }
    }

    /// Moves the plan's items to the Trash. Returns nil when Apply isn't allowed.
    @discardableResult
    public func applyPlan() async -> ExecutionReport? {
        guard canApply, let plan, let tree else { return nil }
        refineToken?.cancel()
        let token = CancelToken()
        applyToken = token
        isApplying = true
        applyProgress = 0
        let report = await executor.execute(plan, progress: { [weak self] fraction in
            Task { @MainActor in self?.applyProgress = fraction }
        }, isCancelled: { token.isCancelled })
        isApplying = false
        applyProgress = nil
        finishApply(report, tree: tree)
        return report
    }

    /// Stops an Apply that is running. Items already moved stay moved, and can be undone.
    public func cancelApply() { applyToken?.cancel() }

    /// Records what moved: removes it from the views, clears its marks, and offers undo.
    private func finishApply(_ report: ExecutionReport, tree: FileTree) {
        lastExecution = report
        canUndoApply = executor.canUndo
        let moved = report.moved.map(\.original)
        guard !moved.isEmpty else {
            post(summary(of: report))
            scheduleLens()
            return
        }
        trashedPaths.formUnion(moved)
        decisionStore.set(.none, paths: moved, tree: tree)
        applyClearedVersion = decisionStore.version
        decisionVersion = decisionStore.version
        selectionPaths.subtract(moved)
        refreshSelection()
        review = nil
        hover = nil
        scheduleLens()
        post(summary(of: report) + " \(Format.bytes(report.bytesMoved)) frees up when you empty it.") { [weak self] in
            guard let self else { return }
            Task { await self.undoApply() }
        }
    }

    /// One plain sentence about what an execution did.
    private func summary(of report: ExecutionReport) -> String {
        var parts = ["Moved \(report.moved.count) \(report.moved.count == 1 ? "item" : "items") to the Trash."]
        if !report.skippedChanged.isEmpty { parts.append("\(report.skippedChanged.count) changed since the scan and were left alone.") }
        if !report.failed.isEmpty { parts.append("\(report.failed.count) couldn't be moved.") }
        return parts.joined(separator: " ")
    }

    /// Puts the last Apply back and restores the marks it cleared.
    @discardableResult
    public func undoApply() async -> ExecutionReport? {
        guard let report = await executor.undoLast() else { return nil }
        canUndoApply = executor.canUndo
        let restored = report.moved.map(\.original)
        trashedPaths.subtract(restored)
        if let tree, !restored.isEmpty {
            if applyClearedVersion == decisionStore.version { decisionStore.undo() } else { decisionStore.set(.remove, paths: restored, tree: tree) }
            decisionVersion = decisionStore.version
        }
        applyClearedVersion = nil
        scheduleLens()
        post(restored.isEmpty ? "Nothing could be put back." : "Put \(restored.count) \(restored.count == 1 ? "item" : "items") back.")
        return report
    }
}
