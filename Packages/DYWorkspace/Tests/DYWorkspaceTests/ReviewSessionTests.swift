import DYCore
import XCTest
@testable import DYWorkspace

final class ReviewSessionTests: XCTestCase {
    private func session() -> ReviewSession {
        ReviewSession(title: "Test", items: (1...4).map {
            ReviewItem(path: "/a/\($0)", name: "\($0)", bytes: UInt64($0) * 100, kind: .other, isDirectory: false)
        })
    }

    func testVerdictAdvancesAndTallies() {
        var review = session()
        XCTAssertEqual(review.record(.keep), "/a/1")
        XCTAssertEqual(review.record(.remove), "/a/2")
        XCTAssertEqual(review.record(.later), "/a/3")
        XCTAssertEqual(review.index, 3)
        let tally = review.tally
        XCTAssertEqual([tally.kept, tally.removed, tally.later, tally.left], [1, 1, 1, 1])
        XCTAssertEqual(tally.removedBytes, 200)
        XCTAssertEqual(tally.decidedBytes, 600)
    }

    func testFinishedAfterLastItem() {
        var review = session()
        for _ in 0..<4 { review.record(.keep) }
        XCTAssertTrue(review.isFinished)
        XCTAssertNil(review.current)
        XCTAssertNil(review.record(.keep))
    }

    func testStepBackRestoresPreviousVerdict() {
        var review = session()
        review.record(.keep)
        review.go(to: 0)
        review.record(.remove)
        XCTAssertEqual(review.verdicts["/a/1"], .remove)
        XCTAssertEqual(review.stepBack(), "/a/1")
        XCTAssertEqual(review.verdicts["/a/1"], .keep)
        XCTAssertEqual(review.index, 0)
        XCTAssertEqual(review.stepBack(), "/a/1")
        XCTAssertNil(review.verdicts["/a/1"])
        XCTAssertNil(review.stepBack())
    }

    func testGoIgnoresOutOfRange() {
        var review = session()
        review.go(to: 2)
        XCTAssertEqual(review.index, 2)
        review.go(to: 99)
        review.go(to: -1)
        XCTAssertEqual(review.index, 2)
    }
}
