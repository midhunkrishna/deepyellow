import DYCore
import Darwin
import Foundation
import os

/// Scans a directory tree with parallel `getattrlistbulk` workers feeding one aggregator thread.
///
/// A scanner runs once. `start()` returns a stream that always ends with `.finished`, even after `cancel()`.
public final class DiskScanner: @unchecked Sendable {
    private let options: ScanOptions
    private let cancelFlag = OSAllocatedUnfairLock(initialState: false)
    private let started = OSAllocatedUnfairLock(initialState: false)
    private let partial = OSAllocatedUnfairLock(initialState: false)

    /// Creates a scanner. Nothing is read until `start()`.
    public init(options: ScanOptions) {
        var options = options
        options.root = ScanPlan.normalize(options.root)
        options.workers = max(1, options.workers)
        self.options = options
    }

    /// True when cancellation cut the scan short, so the finished tree is partial.
    public var wasCancelled: Bool { partial.withLock { $0 } }

    /// Starts the scan on background threads and streams its events.
    public func start() -> AsyncStream<ScanEvent> {
        let alreadyStarted = started.withLock { state -> Bool in
            defer { state = true }
            return state
        }
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            guard !alreadyStarted else { continuation.finish(); return }
            continuation.onTermination = { [weak self] reason in
                if case .cancelled = reason { self?.cancel() }
            }
            let thread = Thread { [self] in
                runScan(continuation)
                continuation.finish()
            }
            thread.name = "DYScan.aggregator"
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 22
            thread.start()
        }
    }

    /// Asks the scan to stop. Directories not yet read are left unexpanded and flagged unreadable.
    public func cancel() { cancelFlag.withLock { $0 = true } }

    private var isCancelled: Bool { cancelFlag.withLock { $0 } }

    /// Runs every pass of the scan on the calling thread and yields the final tree.
    private func runScan(_ continuation: AsyncStream<ScanEvent>.Continuation) {
        let clock = ContinuousClock.now
        let phases = ScanPlan.phases(forRoot: options.root)
        let assembler = TreeAssembler(rootPath: options.root, phase: phases[0], workers: options.workers)
        let jobs = WorkQueue<ScanJob>()
        let results = WorkQueue<DirectoryBatch>()
        let workers = spawnWorkers(jobs: jobs, results: results)
        var reporter = ProgressReporter(options: options, started: clock)

        for phase in phases {
            assembler.begin(phase: phase)
            let context = PhaseContext(rootDevice: DeviceProbe.realDevice(ofPath: phase.path), policy: phase.policy,
                                       exactPrivateSize: options.exactReclaimable)
            jobs.push(ScanJob(token: .root, path: Array(phase.path.utf8) + [0], context: context, followSymlink: true))
            drain(assembler: assembler, results: results, reporter: &reporter, continuation: continuation)
        }
        jobs.close()
        workers.wait()

        partial.withLock { $0 = assembler.skippedDirectories > 0 }
        let meta = ScanMeta(rootPath: options.root, scannedAt: Date(), duration: reporter.elapsed(),
                            unreadableDirectories: assembler.unreadable, limitedByPermissions: assembler.permissionDenied,
                            hardlinkBytesSaved: assembler.hardlinkBytesSaved, cloneBytesSaved: assembler.cloneBytesSaved)
        continuation.yield(.finished(assembler.builder.freeze(meta: meta)))
    }

    /// Consumes batches until every queued directory of the current pass has been assembled.
    private func drain(assembler: TreeAssembler, results: WorkQueue<DirectoryBatch>,
                       reporter: inout ProgressReporter, continuation: AsyncStream<ScanEvent>.Continuation) {
        // Workers queue subdirectory jobs themselves, always after sending the parent's batch, so a directory's
        // batch is applied before its children's and the totals below can't reach equality early.
        var outstanding = 1
        while outstanding > 0 {
            for batch in results.popAll(until: reporter.nextDeadline()) {
                outstanding += assembler.apply(batch) - 1
            }
            reporter.emitIfDue(assembler: assembler, continuation: continuation)
        }
    }

    /// Starts the reader threads. Each takes jobs until the queue closes and sends back one batch per job.
    private func spawnWorkers(jobs: WorkQueue<ScanJob>, results: WorkQueue<DirectoryBatch>) -> DispatchGroup {
        let group = DispatchGroup()
        for index in 0..<options.workers {
            group.enter()
            let thread = Thread { [self] in
                DatalessPolicy.disableMaterialization()
                let reader = DirectoryReader(workerIndex: index)
                while let job = jobs.popLast() {
                    if isCancelled {
                        results.push(DirectoryBatch(token: job.token, path: job.path, skipped: true, context: job.context))
                        continue
                    }
                    let batch = reader.read(job)
                    results.push(batch)
                    jobs.push(contentsOf: DirectoryReader.childJobs(of: batch))
                }
                group.leave()
            }
            thread.name = "DYScan.worker.\(index)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        return group
    }
}

/// Turns the scan's running state into throttled progress and snapshot events.
struct ProgressReporter {
    private let options: ScanOptions
    private let started: ContinuousClock.Instant
    private var lastProgress: ContinuousClock.Instant
    private var lastSnapshot: ContinuousClock.Instant
    private var snapshotCost: Duration = .zero

    /// Creates a reporter whose clock started at `started`.
    init(options: ScanOptions, started: ContinuousClock.Instant) {
        self.options = options
        self.started = started
        lastProgress = started
        lastSnapshot = started
    }

    /// Seconds since the scan began.
    func elapsed() -> TimeInterval { Self.seconds(ContinuousClock.now - started) }

    /// When the aggregator should next wake even if no batch arrives.
    func nextDeadline() -> Date { Date(timeIntervalSinceNow: max(0.01, options.snapshotInterval)) }

    /// Emits a progress event, and when affordable a snapshot, if the interval has passed.
    mutating func emitIfDue(assembler: TreeAssembler, continuation: AsyncStream<ScanEvent>.Continuation) {
        let now = ContinuousClock.now
        guard Self.seconds(now - lastProgress) >= options.snapshotInterval else { return }
        lastProgress = now
        continuation.yield(.progress(ScanProgress(
            files: assembler.files, directories: assembler.directories, bytes: assembler.builder.totalAllocated,
            unreadable: assembler.unreadable, elapsed: Self.seconds(now - started),
            currentPath: String(decoding: assembler.currentPath.dropLast(), as: UTF8.self))))
        // A snapshot stalls the aggregator, so wait at least eight times as long as the last one took.
        guard now - lastSnapshot >= max(.seconds(options.snapshotInterval), snapshotCost * 8) else { return }
        let begun = ContinuousClock.now
        let meta = ScanMeta(rootPath: options.root, duration: Self.seconds(now - started),
                            unreadableDirectories: assembler.unreadable, limitedByPermissions: assembler.permissionDenied)
        continuation.yield(.snapshot(assembler.builder.snapshot(maxNodes: options.snapshotMaxNodes, meta: meta)))
        snapshotCost = ContinuousClock.now - begun
        lastSnapshot = ContinuousClock.now
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

/// Keeps listing a directory from downloading iCloud placeholders.
enum DatalessPolicy {
    private static let typeMaterializeDatalessFiles: Int32 = 3
    private static let scopeThread: Int32 = 1
    private static let materializeOff: Int32 = 1

    /// Turns materialization off for the calling thread.
    static func disableMaterialization() {
        _ = setiopolicy_np(typeMaterializeDatalessFiles, scopeThread, materializeOff)
    }
}

/// Finds the physical device of a path, which `st_dev` cannot do for volume groups.
enum DeviceProbe {
    /// The real device id of the volume holding `path`, or nil if it can't be read.
    static func realDevice(ofPath path: String) -> UInt32? {
        var request = attrlist()
        request.bitmapcount = 5
        request.commonattr = Bulk.cmnReturnedAttributes
        request.forkattr = Bulk.extRealDeviceID
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { getattrlist(path, &request, $0.baseAddress, 64, UInt32(Bulk.optionExtendedCommon)) }
        guard status == 0 else { return statDevice(path) }
        return buffer.withUnsafeBytes { raw -> UInt32? in
            guard raw.loadUnaligned(fromByteOffset: 4 + 16, as: UInt32.self) & Bulk.extRealDeviceID != 0 else { return nil }
            return raw.loadUnaligned(fromByteOffset: 24, as: UInt32.self)
        } ?? statDevice(path)
    }

    private static func statDevice(_ path: String) -> UInt32? {
        var info = stat()
        return stat(path, &info) == 0 ? UInt32(truncatingIfNeeded: info.st_dev) : nil
    }
}
