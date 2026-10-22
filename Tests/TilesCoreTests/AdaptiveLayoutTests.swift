import XCTest
@testable import TilesCore

final class AdaptiveLayoutTests: XCTestCase {
    private func sizes(_ layout: Layout, _ size: CGSize) -> [CGSize] {
        switch layout {
        case .pane: return [size]
        case .split(_, let axis, let ratio, let a, let b):
            let available = (axis == .columns ? size.width : size.height) - 10
            let first = available * ratio, second = available - first
            return sizes(a, axis == .columns ? CGSize(width: first, height: size.height) : CGSize(width: size.width, height: first))
                + sizes(b, axis == .columns ? CGSize(width: second, height: size.height) : CGSize(width: size.width, height: second))
        }
    }
    func testTilingOneThroughEightKeepsOrderAndReadableSizes() throws {
        for count in 1...8 {
            let ids = (0..<count).map { _ in UUID() }
            let layout = try XCTUnwrap(Layout.tiled(ids, size: CGSize(width: 1488, height: 760)))
            XCTAssertEqual(layout.paneIDs, ids)
            for size in sizes(layout, CGSize(width: 1488, height: 760)) {
                XCTAssertGreaterThanOrEqual(size.width, 280)
                XCTAssertGreaterThanOrEqual(size.height, 160)
            }
            let restored = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(layout))
            XCTAssertEqual(layout, restored)
        }
        XCTAssertNil(Layout.tiled([], size: .zero))
    }
    func testNarrowAndPortraitCanvasesHaveNoMissingOrDuplicatedPanes() throws {
        let ids = (0..<8).map { _ in UUID() }
        for canvas in [CGSize(width: 880, height: 330), CGSize(width: 700, height: 1400)] {
            let layout = try XCTUnwrap(Layout.tiled(ids, size: canvas))
            XCTAssertEqual(layout.paneIDs, ids)
            for size in sizes(layout, canvas) {
                XCTAssertGreaterThan(size.width, 100); XCTAssertGreaterThan(size.height, 80)
            }
        }
    }
}
