import DYCore
import XCTest
@testable import DYLenses

final class ThemeTests: XCTestCase {
    func testEveryKindHasAColour() {
        for kind in FileKind.allCases { _ = Theme.kind(kind) }
    }
}
