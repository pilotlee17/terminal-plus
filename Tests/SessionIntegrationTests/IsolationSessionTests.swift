import XCTest
import Darwin
import TilesCore
@testable import CodexTiles

final class TerminalSessionTests: XCTestCase {
    func testBatchCloseOnlySelectedSessions() throws {
        let service = SessionService(socket: "tiles-batch-test-" + UUID().uuidString.lowercased())
        guard service.tmux != nil else { throw XCTSkip("tmux required") }
        defer { _ = try? service.run(["kill-server"]) }
        let panes = (0..<3).map { Pane(title: "batch-\($0)", directory: "/tmp") }
        let started = expectation(description: "three terminals"); started.expectedFulfillmentCount = 3
        for pane in panes {
            service.prepare(pane) { result in
                if case .failure(let error) = result { XCTFail(error.localizedDescription) }; started.fulfill()
            }
        }
        wait(for: [started], timeout: 12)
        let survivor = panes[0]
        let pid = try service.run(["display-message", "-p", "-t", survivor.sessionName, "#{pane_pid}"])
        let closed = expectation(description: "two selected terminals closed"); closed.expectedFulfillmentCount = 2
        for pane in panes.suffix(2) {
            service.kill(pane) { result in
                if case .failure(let error) = result { XCTFail(error.localizedDescription) }; closed.fulfill()
            }
        }
        wait(for: [closed], timeout: 8)
        for pane in panes.suffix(2) { XCTAssertThrowsError(try service.run(["has-session", "-t", pane.sessionName])) }
        XCTAssertEqual(try service.run(["display-message", "-p", "-t", survivor.sessionName, "#{pane_pid}"]), pid)
    }
    func testPlainTerminalStartsWithoutGitAndTracksDirectoryWithoutTouchingSibling() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tiles-plain-" + UUID().uuidString).resolvingSymlinksInPath()
        var child = root.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        child = child.resolvingSymlinksInPath()
        let service = SessionService(socket: "tiles-test-" + UUID().uuidString.lowercased())
        guard service.tmux != nil else { throw XCTSkip("tmux required") }
        defer { _ = try? service.run(["kill-server"]); try? FileManager.default.removeItem(at: root) }
        let first = Pane(title: "one", directory: root.path)
        let started = expectation(description: "plain shell")
        service.prepare(first) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }; started.fulfill()
        }
        wait(for: [started], timeout: 8)
        _ = try service.run(["send-keys", "-t", first.sessionName, "cd child", "Enter"])
        func canonical(_ path: String) -> String {
            guard let pointer = realpath(path, nil) else { return path }
            defer { free(pointer) }; return String(cString: pointer)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while canonical(try service.run(["display-message", "-p", "-t", first.sessionName, "#{pane_current_path}"])) != canonical(child.path) && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let status = expectation(description: "current directory")
        service.statuses { values in XCTAssertEqual(values[first.sessionName].map { canonical($0.directory) }, canonical(child.path)); status.fulfill() }
        wait(for: [status], timeout: 5)
        let sibling = Pane(title: "two", directory: child.path)
        let second = expectation(description: "sibling shell")
        service.prepare(sibling) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }; second.fulfill()
        }
        wait(for: [second], timeout: 8)
        let siblingPID = try service.run(["display-message", "-p", "-t", sibling.sessionName, "#{pane_pid}"])
        let closed = expectation(description: "close only first")
        service.kill(first) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }; closed.fulfill()
        }
        wait(for: [closed], timeout: 5)
        XCTAssertThrowsError(try service.run(["has-session", "-t", first.sessionName]))
        XCTAssertEqual(try service.run(["display-message", "-p", "-t", sibling.sessionName, "#{pane_pid}"]), siblingPID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path))
        let reattached = expectation(description: "prepare preserves running session")
        service.prepare(sibling) { _ in reattached.fulfill() }
        wait(for: [reattached], timeout: 5)
        XCTAssertEqual(try service.run(["display-message", "-p", "-t", sibling.sessionName, "#{pane_pid}"]), siblingPID)
    }
}
