import XCTest
@testable import TilesCore

final class WorkspaceTests: XCTestCase {
    func testNestedSplitAndClosePreserveOtherSessions() throws {
        var workspace = Workspace(name: "Test", directory: "/tmp")
        let first = workspace.focusedID
        let second = try XCTUnwrap(workspace.addPane(mode: .codex, axis: .columns))
        let third = try XCTUnwrap(workspace.addPane(mode: .shell, axis: .rows))
        XCTAssertTrue(workspace.isValid)
        XCTAssertTrue(workspace.removePane(second.id))
        XCTAssertEqual(workspace.layout.paneIDs, [first, third.id])
        XCTAssertTrue(workspace.isValid)
        XCTAssertTrue(workspace.removePane(third.id))
        XCTAssertFalse(workspace.removePane(first))
        XCTAssertEqual(workspace.layout, .pane(first))
    }
    func testPersistRoundTripAndRejectBrokenLayout() throws {
        var workspace = Workspace(name: "项目", directory: "/tmp/project with spaces")
        _ = workspace.addPane(mode: .codex, axis: .rows)
        _ = workspace.addPane(mode: .claude, axis: .columns)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try StateStore.save(SavedState(workspaces: [workspace], selectedID: workspace.id), to: url)
        let restored = try StateStore.load(from: url)
        XCTAssertEqual(restored.workspaces[0].layout, workspace.layout)
        XCTAssertEqual(restored.workspaces[0].panes, workspace.panes)
        workspace.layout = .pane(UUID())
        XCTAssertThrowsError(try StateStore.save(SavedState(workspaces: [workspace], selectedID: workspace.id), to: url))
    }
    func testPaneLimitAndDuplicateSessionRejection() {
        var workspace = Workspace(name: "Test", directory: "/tmp")
        for _ in 0..<7 { XCTAssertNotNil(workspace.addPane(mode: .shell, axis: .columns)) }
        XCTAssertNil(workspace.addPane(mode: .shell, axis: .rows))
        XCTAssertTrue(workspace.isValid)
        workspace.panes[1] = workspace.panes[0]
        XCTAssertFalse(workspace.isValid)
    }
    func testPathsAreIndependentArgumentsNotShellSource() {
        let path = "/tmp/a 'quoted'; $(touch should-not-exist)\n中文"
        for mode in [PaneMode.codex, .claude] {
        let pane = Pane(title: "test", directory: path, mode: mode)
        let args = SessionArguments.create(pane: pane, executable: "/path with spaces/agent")
        XCTAssertEqual(args[try! XCTUnwrap(args.firstIndex(of: "-c")) + 1], path)
        XCTAssertEqual(Array(args.suffix(2)), ["/usr/bin/env", "/path with spaces/agent"])
        XCTAssertFalse(args.contains("sh"))
        XCTAssertFalse(args.contains("-lc"))
        }
    }
}
