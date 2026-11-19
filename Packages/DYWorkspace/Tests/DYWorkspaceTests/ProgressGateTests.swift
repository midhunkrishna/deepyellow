import XCTest
@testable import DYWorkspace

final class ProgressGateTests: XCTestCase {
    /// 50,000 even steps from 0 to 1 pass at most 101 times.
    func testAcceptsAtMost101OfFiftyThousandUpdates() {
        let gate = ProgressGate()
        let count = 50_000
        let accepted = (0...count).filter { gate.accept(Double($0) / Double(count)) }.count
        XCTAssertLessThanOrEqual(accepted, 101)
        XCTAssertGreaterThan(accepted, 1)
    }

    /// A finished fraction is accepted even right after a nearby value.
    func testAlwaysAcceptsOne() {
        let gate = ProgressGate()
        XCTAssertTrue(gate.accept(0.995))
        XCTAssertTrue(gate.accept(1.0))
    }
}
