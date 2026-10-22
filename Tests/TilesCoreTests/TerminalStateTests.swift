import XCTest
@testable import TilesCore

final class TerminalStateTests: XCTestCase {
    func testLegacyMigrationPreservesSessionIDsAndDirectoriesWithoutAgentModes() throws {
        var active = Workspace(name: "old", directory: "/tmp/project")
        _ = active.addPane(mode: .codex, axis: .columns)
        var other = Workspace(name: "another", directory: "/tmp/other")
        _ = other.addPane(mode: .claude, axis: .rows)
        let legacy = SavedState(workspaces: [active, other], selectedID: active.id)
        var state = TerminalState(legacy: legacy)
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.panes.map(\.id), active.panes.map(\.id))
        XCTAssertEqual(state.panes.map(\.directory), active.panes.map(\.directory))
        XCTAssertEqual(state.parked.map(\.id), other.panes.map(\.id))
        XCTAssertTrue((state.panes + state.parked).allSatisfy { $0.mode == .shell && $0.worktree == nil })
        let restored = state.parked[0]
        XCTAssertTrue(state.insert(restored, axis: .rows))
        XCTAssertFalse(state.parked.contains { $0.id == restored.id })
        XCTAssertTrue(state.isValid)
    }
    func testLastPaneClosesAndEmptyLayoutCanCreateAgainAndPersist() throws {
        var state = TerminalState(directory: "/tmp")
        XCTAssertTrue(state.remove(state.panes[0].id))
        XCTAssertTrue(state.isValid); XCTAssertNil(state.layout); XCTAssertNil(state.focusedID)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("layout.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try state.save(to: url)
        state = try TerminalState.load(from: url)
        XCTAssertTrue(state.panes.isEmpty)
        let pane = Pane(title: "shell", directory: "/tmp")
        XCTAssertTrue(state.insert(pane, axis: .columns))
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.layout, .pane(pane.id))
        XCTAssertFalse(state.insert(pane, axis: .rows))
    }
}
