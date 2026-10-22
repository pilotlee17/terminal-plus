import XCTest
@testable import TilesCore

final class LayoutHistoryTests: XCTestCase {
    func testUndoRedoAndSessionChangesCannotResurrectClosedPanes() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let original = Layout.pane(a).splitting(a, with: b, axis: .columns)
        let changed = original.rearranging(a, relativeTo: b, placement: .bottom)
        var history = LayoutHistory()
        history.record(original, current: changed)
        XCTAssertEqual(history.undo(current: changed), original)
        XCTAssertEqual(history.redo(current: original), changed)
        _ = history.undo(current: changed)
        let different = original.rearranging(a, relativeTo: b, placement: .center)
        history.record(original, current: different)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.undo(current: different.splitting(a, with: c, axis: .rows)))
        XCTAssertFalse(history.canUndo)
    }
    func testHistoryBoundedAndNoopDoesNotConsumeUndo() {
        let a = UUID(), b = UUID(), split = UUID()
        var history = LayoutHistory()
        var current = Layout.split(split, .columns, 0.2, .pane(a), .pane(b))
        for index in 1...50 {
            let next = Layout.split(split, .columns, 0.2 + Double(index) / 100, .pane(a), .pane(b))
            history.record(current, current: next); current = next
        }
        history.record(current, current: current)
        var count = 0
        while let previous = history.undo(current: current) { count += 1; current = previous }
        XCTAssertEqual(count, 30)
    }
    func testCorruptLayoutIdentifiersAndRatiosRejected() {
        let a = UUID(), b = UUID(), c = UUID(), split = UUID()
        XCTAssertFalse(Layout.split(split, .columns, 0.5, .pane(a), .split(split, .rows, 0.5, .pane(b), .pane(c))).hasValidStructure)
        for ratio in [0, 1, Double.nan, Double.infinity, -0.1] {
            XCTAssertFalse(Layout.split(split, .columns, ratio, .pane(a), .pane(b)).hasValidStructure)
        }
    }
    func testCloseFocusFollowsVisualNeighborAfterReorder() {
        var state = TerminalState(directory: "/tmp")
        let a = state.panes[0].id, b = Pane(title: "b", directory: "/tmp"), c = Pane(title: "c", directory: "/tmp")
        state.insert(b, axis: .columns); state.insert(c, axis: .columns)
        state.move(a, relativeTo: c.id, placement: .center)
        XCTAssertEqual(state.layout!.paneIDs, [c.id, b.id, a])
        state.focusedID = c.id; state.remove(c.id)
        XCTAssertEqual(state.focusedID, b.id)
    }
}
