import XCTest
@testable import TilesCore

final class PanePlacementTests: XCTestCase {
    func testEveryMovePreservesSessionsAndCanRoundTrip() throws {
        var original = TerminalState(directory: "/tmp")
        for index in 1...4 {
            XCTAssertTrue(original.insert(Pane(title: "terminal \(index)", directory: "/tmp/\(index)"), axis: index % 2 == 0 ? .rows : .columns))
        }
        let ids = original.layout!.paneIDs
        for source in ids {
            for target in ids where source != target {
                for placement in PanePlacement.allCases {
                    var moved = original
                    XCTAssertTrue(moved.move(source, relativeTo: target, placement: placement))
                    XCTAssertTrue(moved.isValid)
                    XCTAssertEqual(moved.panes, original.panes)
                    XCTAssertEqual(moved.parked, original.parked)
                    XCTAssertEqual(moved.focusedID, source)
                    XCTAssertEqual(Set(moved.layout!.paneIDs), Set(ids))
                    let restored = try JSONDecoder().decode(TerminalState.self, from: JSONEncoder().encode(moved))
                    XCTAssertTrue(restored.isValid)
                    XCTAssertEqual(restored.layout, moved.layout)
                    let order = moved.layout!.paneIDs
                    if placement == .center {
                        XCTAssertEqual(order[ids.firstIndex(of: source)!], target)
                        XCTAssertEqual(order[ids.firstIndex(of: target)!], source)
                    } else {
                        let sourceIndex = order.firstIndex(of: source)!, targetIndex = order.firstIndex(of: target)!
                        XCTAssertEqual(sourceIndex - targetIndex, placement == .left || placement == .top ? -1 : 1)
                    }
                }
            }
        }
    }
    func testEdgesCollapseOldSplitAndKeepUnrelatedRatios() {
        let a = UUID(), b = UUID(), c = UUID(), root = UUID()
        let layout = Layout.split(root, .columns, 0.3, .split(UUID(), .rows, 0.6, .pane(a), .pane(b)), .pane(c))
        for placement in [PanePlacement.left, .right, .top, .bottom] {
            let moved = layout.rearranging(a, relativeTo: c, placement: placement)
            guard case .split(let id, .columns, let ratio, .pane(let remaining), .split(_, let axis, _, .pane(let first), .pane(let second))) = moved else {
                XCTFail("Wrong tree shape"); continue
            }
            XCTAssertEqual(id, root); XCTAssertEqual(ratio, 0.3); XCTAssertEqual(remaining, b)
            XCTAssertEqual(axis, placement == .left || placement == .right ? .columns : .rows)
            XCTAssertEqual(first, placement == .left || placement == .top ? a : c)
            XCTAssertEqual(second, placement == .left || placement == .top ? c : a)
        }
        XCTAssertEqual(layout.rearranging(a, relativeTo: a, placement: .left), layout)
        XCTAssertEqual(layout.rearranging(UUID(), relativeTo: c, placement: .center), layout)
    }
}
