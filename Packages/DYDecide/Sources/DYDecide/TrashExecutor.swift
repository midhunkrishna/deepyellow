import Foundation

/// Moves the items of a plan to the Trash and puts them back on request.
///
/// There is no code path that deletes. Every change is a move, and each move is journaled before and after it
/// happens, so the last execution can be undone even after a crash.
public final class TrashExecutor: @unchecked Sendable {
    private let mover: TrashMoving
    private let file: JournalFile
    private let lock = NSLock()
    private var journal: Journal

    /// Creates an executor. A `journalURL` of nil keeps the undo journal in memory only.
    public init(mover: TrashMoving, journalURL: URL?) {
        self.mover = mover
        self.file = JournalFile(url: journalURL)
        self.journal = file.load()
    }

    /// Whether the last execution has anything left to put back.
    public var canUndo: Bool { lock.withLock { !journal.entries.isEmpty } }

    /// Moves each item to the Trash, skipping any that changed since the plan was made.
    ///
    /// Cancellation is checked before each item. Items not reached are listed in `notAttempted`, and the report
    /// holds exactly what was moved. `progress` receives the fraction of items handled.
    public func execute(_ plan: RemovalPlan, progress: @Sendable (Double) -> Void,
                        isCancelled: @Sendable () -> Bool) async -> ExecutionReport {
        let (accepted, refused) = PlanSanity.partition(plan.items)
        var report = ExecutionReport(failed: refused.map { (path: $0.path, error: $0.reason) })
        var batch = Journal()
        for (index, item) in accepted.enumerated() {
            if isCancelled() || Task.isCancelled {
                report.notAttempted = accepted[index...].map(\.id)
                return report
            }
            progress(Double(index) / Double(accepted.count))
            move(item, into: &report, journal: &batch)
            await Task.yield()
        }
        progress(1)
        return report
    }

    /// Puts the last execution's items back where they came from, never overwriting anything.
    ///
    /// Items that can't be restored stay in the journal, so a later call can retry them.
    /// Returns nil when there is nothing to undo.
    public func undoLast() async -> ExecutionReport? {
        let entries = lock.withLock { journal.entries }
        guard !entries.isEmpty else { return nil }
        var report = ExecutionReport()
        for entry in entries.reversed() {
            let outcome = restore(entry)
            switch outcome {
            case .restored(let trashed):
                report.moved.append((original: entry.original, trashed: trashed))
                report.bytesMoved += entry.bytes
                forget(entry)
            case .failed(let reason, let keep):
                report.failed.append((path: entry.original, error: reason))
                if !keep { forget(entry) }
            }
            await Task.yield()
        }
        return report
    }

    // MARK: - Moving

    /// Journals, checks the fingerprint, moves one item, and records the outcome in `report`.
    private func move(_ item: PlanItem, into report: inout ExecutionReport, journal batch: inout Journal) {
        do {
            guard try mover.currentFingerprint(path: item.id) == item.fingerprint else {
                report.skippedChanged.append(item.id)
                return
            }
        } catch {
            report.failed.append((path: item.id, error: "Couldn't check it before moving: \(error)"))
            return
        }
        batch.entries.append(JournalEntry(original: item.id, trashed: nil, state: .moving, bytes: item.bytes))
        guard publish(batch) else {
            batch.entries.removeLast()
            report.failed.append((path: item.id, error: "Couldn't write the undo journal, so nothing was moved"))
            return
        }
        do {
            let trashed = try mover.moveToTrash(path: item.id)
            batch.entries[batch.entries.count - 1].trashed = trashed
            batch.entries[batch.entries.count - 1].state = .moved
            _ = publish(batch)
            report.moved.append((original: item.id, trashed: trashed))
            report.bytesMoved += item.bytes
        } catch {
            batch.entries.removeLast()
            _ = publish(batch)
            report.failed.append((path: item.id, error: "\(error)"))
        }
    }

    /// Makes `batch` the current journal and saves it. Returns false when the save failed.
    private func publish(_ batch: Journal) -> Bool {
        lock.withLock {
            journal = batch
            return file.save(journal)
        }
    }

    // MARK: - Undoing

    private enum RestoreOutcome {
        case restored(trashed: String)
        /// `keep` leaves the entry in the journal for another try.
        case failed(reason: String, keep: Bool)
    }

    /// Puts one entry back, after checking that the Trash copy exists and the original spot is free.
    private func restore(_ entry: JournalEntry) -> RestoreOutcome {
        guard entry.state == .moved, let trashed = entry.trashed else {
            return .failed(reason: "The move was interrupted. Look for it in the Trash", keep: false)
        }
        guard mover.exists(path: trashed) else {
            return .failed(reason: "No longer in the Trash", keep: false)
        }
        guard !mover.exists(path: entry.original) else {
            return .failed(reason: "Something already exists at the original location", keep: true)
        }
        do {
            try mover.moveBack(from: trashed, to: entry.original)
            return .restored(trashed: trashed)
        } catch {
            return .failed(reason: "\(error)", keep: true)
        }
    }

    /// Drops a finished entry from the journal and saves.
    private func forget(_ entry: JournalEntry) {
        lock.withLock {
            journal.entries.removeAll { $0.original == entry.original }
            _ = file.save(journal)
        }
    }
}
