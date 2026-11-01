import DYCore
import XCTest
@testable import DYWorkspace

final class ReviewSessionTests: XCTestCase {
    private func session() -> ReviewSession {
        ReviewSession(title: "Test", items: (1...4).map {
            ReviewItem(path: "/a/\($0)", name: "\($0)", bytes: UInt64($0) * 100, kind: .other, isDirectory: false)
        })
    }

    func testVerdictStaysAndTallies() {
        var review = session()
        XCTAssertEqual(review.record(.keep), "/a/1")
        XCTAssertEqual(review.index, 0)
        review.go(to: 1)
        XCTAssertEqual(review.record(.remove), "/a/2")
        review.go(to: 2)
        XCTAssertEqual(review.record(.later), "/a/3")
        let verdicts = review.verdicts
        let tally = review.tally { verdicts[$0.path] ?? .none }
        XCTAssertEqual([tally.kept, tally.removed, tally.later, tally.left], [1, 1, 1, 1])
        XCTAssertEqual(tally.removedBytes, 200)
        XCTAssertEqual(tally.decidedBytes, 600)
    }

    func testStepBackAndForwardRestoreVerdictsAndPlace() {
        var review = session()
        review.record(.keep)
        review.record(.remove)
        review.go(to: 3)
        XCTAssertEqual(review.verdicts["/a/1"], .remove)
        XCTAssertEqual(review.stepBack(), "/a/1")
        XCTAssertEqual(review.verdicts["/a/1"], .keep)
        XCTAssertEqual(review.index, 0)
        XCTAssertEqual(review.stepForward(), "/a/1")
        XCTAssertEqual(review.verdicts["/a/1"], .remove)
        XCTAssertNil(review.stepForward())
        review.stepBack()
        XCTAssertEqual(review.stepBack(), "/a/1")
        XCTAssertNil(review.verdicts["/a/1"])
        XCTAssertNil(review.stepBack())
    }

    func testANewVerdictClearsRedo() {
        var review = session()
        review.record(.keep)
        review.stepBack()
        review.record(.remove)
        XCTAssertNil(review.stepForward())
    }

    func testGoIgnoresOutOfRange() {
        var review = session()
        review.go(to: 2)
        XCTAssertEqual(review.index, 2)
        review.go(to: 4)
        review.go(to: -1)
        XCTAssertEqual(review.index, 2)
        review.go(to: 3)
        XCTAssertTrue(review.isAtEnd)
    }

    func testEnterStartsAtTheFirstItemAndLeaveReturnsToTheSamePlace() {
        var review = session()
        review.go(to: 2)
        let inside = [ReviewItem(path: "/a/3/x", name: "x", bytes: 1, kind: .other, isDirectory: false),
                      ReviewItem(path: "/a/3/y", name: "y", bytes: 1, kind: .other, isDirectory: false)]
        review.enter(title: "3", items: inside)
        XCTAssertEqual(review.depth, 1)
        XCTAssertEqual(review.index, 0)
        XCTAssertEqual(review.current?.path, "/a/3/x")
        XCTAssertEqual(review.trail, ["Test", "3"])
        XCTAssertTrue(review.leave())
        XCTAssertEqual(review.depth, 0)
        XCTAssertEqual(review.current?.path, "/a/3")
        XCTAssertEqual(review.trail, ["Test"])
        XCTAssertFalse(review.leave())
    }

    func testEnteringNothingIsIgnoredAndUndoAcrossLevelsKeepsThePlace() {
        var review = session()
        review.record(.remove)
        review.enter(title: "empty", items: [])
        XCTAssertEqual(review.depth, 0)
        review.enter(title: "1", items: [ReviewItem(path: "/a/1/x", name: "x", bytes: 1, kind: .other, isDirectory: false)])
        XCTAssertEqual(review.stepBack(), "/a/1")
        XCTAssertEqual(review.current?.path, "/a/1/x")
        XCTAssertNil(review.verdicts["/a/1"])
    }
}
