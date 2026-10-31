import DYCore
import XCTest
@testable import DYDecide

/// A probe that answers from a table and records what it was asked.
private final class TableProbe: ReclaimProbing, @unchecked Sendable {
    let answers: [String: UInt64]
    init(_ answers: [String: UInt64]) { self.answers = answers }
    func privateBytes(path: String) -> UInt64? { answers[path] }
}

final class PlanRefinerTests: XCTestCase {
    private func item(_ path: String, bytes: UInt64, reclaimable: UInt64, floor: Bool) -> PlanItem {
        PlanItem(id: path, node: 1, bytes: bytes, reclaimable: reclaimable,
                 fingerprint: Fingerprint(size: 1, modified: 1, inode: 1), reclaimIsLowerBound: floor)
    }

    /// Probed items take the measured figure; a shared item stays a floor and an exact one stops being one.
    func testProbedFiguresReplaceEstimates() async {
        let plan = RemovalPlan(items: [item("/a", bytes: 100, reclaimable: 100, floor: true),
                                       item("/b", bytes: 100, reclaimable: 100, floor: false)])
        let refined = await RemovalPlanner.refine(plan, probe: TableProbe(["/a": 100, "/b": 40]), isCancelled: { false })
        XCTAssertEqual(refined.items.map(\.reclaimable), [100, 40])
        XCTAssertEqual(refined.items.map(\.reclaimIsLowerBound), [false, true])
        XCTAssertEqual(refined.totalReclaimable, 140)
        XCTAssertTrue(refined.estimateIsLowerBound)
    }

    /// A probe that fails keeps the value and never leaves an item claiming "at least".
    func testFailedProbeKeepsValueAndDropsFloorClaim() async {
        let plan = RemovalPlan(items: [item("/a", bytes: 100, reclaimable: 70, floor: true)])
        let refined = await RemovalPlanner.refine(plan, probe: TableProbe([:]), isCancelled: { false })
        XCTAssertEqual(refined.items[0].reclaimable, 70)
        XCTAssertFalse(refined.items[0].reclaimIsLowerBound)
        XCTAssertFalse(refined.estimateIsLowerBound)
    }

    /// A measurement above the allocated size is capped at it.
    func testMeasurementIsCappedAtAllocated() async {
        let plan = RemovalPlan(items: [item("/a", bytes: 100, reclaimable: 10, floor: true)])
        let refined = await RemovalPlanner.refine(plan, probe: TableProbe(["/a": 900]), isCancelled: { false })
        XCTAssertEqual(refined.items[0].reclaimable, 100)
    }

    /// Cancelling returns the plan untouched.
    func testCancelledReturnsOriginal() async {
        let plan = RemovalPlan(items: [item("/a", bytes: 100, reclaimable: 70, floor: true)])
        let refined = await RemovalPlanner.refine(plan, probe: TableProbe(["/a": 5]), isCancelled: { true })
        XCTAssertEqual(refined.items[0].reclaimable, 70)
    }

    /// The plan-level flag defaults to whether any item is a floor.
    func testPlanFlagDefault() {
        XCTAssertFalse(RemovalPlan(items: [item("/a", bytes: 1, reclaimable: 1, floor: false)]).estimateIsLowerBound)
        XCTAssertTrue(RemovalPlan(items: [item("/a", bytes: 1, reclaimable: 1, floor: true)]).estimateIsLowerBound)
    }

    /// A file with a resource fork fingerprints at the size of all forks, as the scanner records.
    func testFingerprintCountsResourceFork() throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let path = try sandbox.file("forked.bin", String(repeating: "d", count: 1000))
        let plain = try Fingerprint.current(path: path)
        XCTAssertEqual(plain.size, 1000)
        let descriptor = open(path + "/..namedfork/rsrc", O_WRONLY | O_CREAT, 0o644)
        try XCTSkipIf(descriptor < 0, "this volume has no resource forks")
        let payload = [UInt8](repeating: 7, count: 300)
        XCTAssertEqual(write(descriptor, payload, payload.count), 300)
        close(descriptor)
        XCTAssertEqual(try Fingerprint.current(path: path).size, 1300)
    }
}
