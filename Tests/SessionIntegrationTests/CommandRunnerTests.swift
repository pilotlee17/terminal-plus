import XCTest
import TilesCore
@testable import CodexTiles

final class CommandRunnerTests: XCTestCase {
    private func run(_ script: String, timeout: TimeInterval = 1) throws -> String {
        try CommandRunner.run(executable: "/bin/sh", arguments: ["-c", script], environment: ProcessInfo.processInfo.environment, timeout: timeout).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testInheritedPipeDoesNotBlockNextControlCommand() throws {
        let started = ProcessInfo.processInfo.systemUptime
        // Child exits promptly while a descendant holds stdout for three seconds.
        XCTAssertEqual(try run("/bin/sleep 3 & printf ready"), "ready")
        XCTAssertEqual(try run("printf next-command"), "next-command")
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1.5)
    }

    func testTimeoutEscalatesWhenCommandIgnoresTermination() throws {
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try run("trap '' TERM; while :; do :; done", timeout: 0.15)) { error in
            XCTAssertTrue(error.localizedDescription.contains("超时"))
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1.5)
        XCTAssertEqual(try run("printf recovered"), "recovered")
    }

    func testLargeOutputDrainsWithoutDeadlockAndReportsErrors() throws {
        XCTAssertEqual(try run("/usr/bin/yes x | /usr/bin/head -c 131072").utf8.count, 32767)
        XCTAssertThrowsError(try run("printf 'explicit failure' >&2; exit 2")) { error in
            XCTAssertEqual(error.localizedDescription, "explicit failure")
        }
    }
}
