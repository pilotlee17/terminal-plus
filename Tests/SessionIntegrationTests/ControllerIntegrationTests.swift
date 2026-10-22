import XCTest
import AppKit
import Darwin
import TilesCore
@testable import CodexTiles

final class ControllerIntegrationTests: XCTestCase {
    var root: URL!
    var service: SessionService!
    var controller: TilesController!
    var errors: [String] = []

    override func setUpWithError() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-plus-test-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("child"), withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        service = SessionService(socket: "terminal-plus-test-" + UUID().uuidString.lowercased())
        guard service.tmux != nil else { throw XCTSkip("tmux required") }
        try TerminalState(directory: root.path).save(to: root.appendingPathComponent("terminal-layout.json"))
        controller = makeController()
    }
    func makeController() -> TilesController {
        TilesController(storageRoot: root, service: service, startTimer: false, reportError: { [weak self] in self?.errors.append($0) })
    }
    override func tearDownWithError() throws {
        controller?.pendingSave?.cancel(); controller?.detachAll(); controller?.window?.close()
        service?.queue.sync {}
        _ = try? service?.run(["kill-server"])
        controller = nil
        if let root { try? FileManager.default.removeItem(at: root) }
    }
    func eventually(_ description: String, timeout: TimeInterval = 20, _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), description, file: file, line: line)
    }
    func ready() {
        eventually("all panes attached on the isolated service") {
            self.controller.pendingConnections.isEmpty && self.controller.panes.values.allSatisfy { !$0.starting && $0.terminal.process.running && $0.failure == nil }
        }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
    }
    func testRapidCreationUsesActualCwdAndCorrectSocketWithoutLostClicks() throws {
        ready()
        func canonical(_ path: String) -> String {
            guard let pointer = realpath(path, nil) else { return path }
            defer { free(pointer) }; return String(cString: pointer)
        }
        let first = controller.state.panes[0], view = controller.panes[first.id]!
        _ = try service.run(["send-keys", "-t", first.sessionName + ":0.0", "cd child", "Enter"])
        eventually("shell changes cwd") {
            (try? self.service.run(["display-message", "-p", "-t", first.sessionName + ":0.0", "#{pane_current_path}"])).map(canonical) == canonical(self.root.appendingPathComponent("child").path)
        }
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<7 { controller.newPanel() }
        print("Seven synchronous pane insertions: \(ProcessInfo.processInfo.systemUptime - start)s")
        XCTAssertEqual(controller.state.panes.count, 8)
        XCTAssertTrue(controller.panes[first.id] === view)
        controller.newPanel(); XCTAssertEqual(controller.state.panes.count, 8)
        ready()
        for pane in controller.state.panes.dropFirst() {
            XCTAssertEqual(canonical(pane.directory), canonical(root.appendingPathComponent("child").path))
            XCTAssertEqual(try service.run(["display-message", "-p", "-t", pane.sessionName + ":0.0", "#{pane_current_path}"]), pane.directory)
        }
        XCTAssertEqual(try service.run(["list-clients", "-F", "#{session_name}"]).split(separator: "\n").count, 8)
        XCTAssertTrue(controller.state.isValid)
    }
    func testLayoutUndoRedoSelectionZoomAndResizeReuseViews() throws {
        for _ in 0..<3 { controller.newPanel() }; ready()
        let views = controller.panes
        let before = controller.state.layout!
        controller.arrangeLayout(); let tiled = controller.state.layout!
        controller.undoLayout(); XCTAssertEqual(controller.state.layout, before)
        controller.redoLayout(); XCTAssertEqual(controller.state.layout, tiled)
        controller.toggleZoom(); XCTAssertTrue(controller.zoomed)
        controller.toggleZoom(); XCTAssertEqual(controller.state.layout, tiled)
        controller.toggleSelection(); controller.toggleSelection()
        for (id, view) in views { XCTAssertTrue(controller.panes[id] === view) }
        for size in [NSSize(width: 900, height: 440), NSSize(width: 1800, height: 1000)] {
            controller.window?.setContentSize(size)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            controller.arrangeLayout()
            XCTAssertTrue(controller.state.isValid)
            XCTAssertTrue(controller.panes.values.allSatisfy { $0.frame.width > 100 && $0.frame.height > 80 })
        }
    }
    func testCloseSubsetAllEmptyReopenAndPendingCreationClose() throws {
        for _ in 0..<3 { controller.newPanel() }; ready()
        let survivor = controller.state.panes[0]
        let pid = try service.run(["display-message", "-p", "-t", survivor.sessionName + ":0.0", "#{pane_pid}"])
        controller.performConfirmedClose(Set(controller.state.panes.dropFirst().map(\.id)))
        eventually("selected panes closed") { self.controller.closingPanes.isEmpty && self.controller.state.panes.count == 1 }
        XCTAssertEqual(try service.run(["display-message", "-p", "-t", survivor.sessionName + ":0.0", "#{pane_pid}"]), pid)
        controller.performConfirmedClose([UUID()]); XCTAssertEqual(controller.state.panes.count, 1)
        controller.performConfirmedClose([survivor.id])
        eventually("last pane closes") { self.controller.closingPanes.isEmpty && self.controller.state.panes.isEmpty }
        XCTAssertNil(controller.state.layout); XCTAssertTrue(controller.state.isValid)
        controller.newPanel()
        controller.performConfirmedClose(Set(controller.state.panes.map(\.id)))
        eventually("pending pane closes without resurrection") { self.controller.pendingConnections.isEmpty && self.controller.closingPanes.isEmpty && self.controller.state.panes.isEmpty }
        service.queue.sync {}
        XCTAssertThrowsError(try service.run(["list-sessions"]))
        controller.newPanel(); ready(); XCTAssertEqual(controller.state.panes.count, 1)
    }
    func testRelaunchRetainsPidAndMissingDirectoryAndCorruptionAreRecoverable() throws {
        ready()
        let pane = controller.state.panes[0]
        let pid = try service.run(["display-message", "-p", "-t", pane.sessionName + ":0.0", "#{pane_pid}"])
        controller.save(); controller.detachAll(); controller.window?.close(); controller = makeController(); ready()
        XCTAssertEqual(try service.run(["display-message", "-p", "-t", pane.sessionName + ":0.0", "#{pane_pid}"]), pid)
        controller.add(axis: nil, directory: root.appendingPathComponent("missing").path)
        eventually("missing directory reports actionable failure") { !self.errors.isEmpty }
        XCTAssertTrue(controller.panes.values.contains { $0.failure?.contains("目录不存在") == true })
        controller.pendingSave?.cancel(); controller.detachAll(); controller.window?.close()
        let corrupt = Data("broken-layout".utf8)
        try corrupt.write(to: root.appendingPathComponent("terminal-layout.json"))
        errors.removeAll(); controller = makeController()
        eventually("corrupt layout notification") { self.errors.contains { $0.contains("已备份") } }
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("terminal-layout-unreadable-") }
        XCTAssertEqual(backups.count, 1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), corrupt)
        XCTAssertTrue(controller.state.isValid)
    }
}
