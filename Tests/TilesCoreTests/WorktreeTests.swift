import XCTest
@testable import TilesCore

final class WorktreeTests: XCTestCase {
    var root: URL!
    var repo: URL!
    var manager: WorktreeManager!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tiles-git-" + UUID().uuidString).resolvingSymlinksInPath()
        repo = root.appendingPathComponent("project 'quoted'; $(touch INJECTED) 中文")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        manager = WorktreeManager(storageURL: root.appendingPathComponent("work trees 中文"))
        try manager.git(repo.path, ["init", "-b", "main"])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func commitFixture() throws {
        try "baseline\n".write(to: repo.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub dir"), withIntermediateDirectories: true)
        try "sub\n".write(to: repo.appendingPathComponent("sub dir/file.txt"), atomically: true, encoding: .utf8)
        try manager.git(repo.path, ["add", "."])
        try manager.git(repo.path, ["-c", "user.name=Tiles Test", "-c", "user.email=tiles@example.invalid", "-c", "commit.gpgSign=false", "commit", "-m", "fixture"])
    }
    func pane(directory: String? = nil) -> Pane { Pane(title: "Codex", directory: directory ?? repo.path, mode: .codex) }

    func testTwoCodexWorktreesHaveIndependentFilesIndexesAndBranches() throws {
        try commitFixture()
        let one = try manager.create(for: pane())
        let two = try manager.create(for: pane())
        XCTAssertNotEqual(one.directory, two.directory)
        XCTAssertNotEqual(one.worktree?.branch, two.worktree?.branch)
        XCTAssertEqual(one.worktree?.baseCommit, two.worktree?.baseCommit)
        XCTAssertEqual(try manager.git(one.directory, ["branch", "--show-current"]), one.worktree?.branch)
        let targets = [one, two]
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            try! "agent-\(index)\n".write(toFile: targets[index].directory + "/shared.txt", atomically: true, encoding: .utf8)
        }
        try manager.git(one.directory, ["add", "shared.txt"])
        XCTAssertEqual(try String(contentsOfFile: one.directory + "/shared.txt"), "agent-0\n")
        XCTAssertEqual(try String(contentsOfFile: two.directory + "/shared.txt"), "agent-1\n")
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("shared.txt")), "baseline\n")
        XCTAssertEqual(try manager.git(repo.path, ["status", "--porcelain"]), "")
        XCTAssertEqual(try manager.git(two.directory, ["diff", "--cached", "--name-only"]), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("INJECTED").path))
    }

    func testDirtySourceIsPreservedAndDoesNotLeakIntoNewCheckout() throws {
        try commitFixture()
        try "local edits\n".write(to: repo.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "private local\n".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        try manager.git(repo.path, ["add", "shared.txt"])
        let before = try manager.git(repo.path, ["status", "--porcelain"])
        let isolated = try manager.create(for: pane())
        XCTAssertEqual(isolated.worktree?.sourceWasDirty, true)
        XCTAssertEqual(try String(contentsOfFile: isolated.directory + "/shared.txt"), "baseline\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.directory + "/untracked.txt"))
        XCTAssertEqual(try manager.git(repo.path, ["status", "--porcelain"]), before)
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("shared.txt")), "local edits\n")
    }

    func testClaudeAndCodexIsolationAndClaudeRestoreKeepToolAndEdits() throws {
        try commitFixture()
        let codex = try manager.create(for: pane())
        let claude = try manager.create(for: Pane(title: "Claude Code", directory: repo.path, mode: .claude))
        XCTAssertNotEqual(codex.directory, claude.directory)
        XCTAssertNotEqual(codex.worktree?.branch, claude.worktree?.branch)
        try "Claude changes".write(toFile: claude.directory + "/shared.txt", atomically: true, encoding: .utf8)
        try manager.git(claude.directory, ["add", "shared.txt"])
        XCTAssertEqual(try String(contentsOfFile: codex.directory + "/shared.txt"), "baseline\n")
        XCTAssertEqual(try manager.git(codex.directory, ["diff", "--cached", "--name-only"]), "")
        var workspace = Workspace(name: "Mixed", directory: repo.path)
        XCTAssertTrue(workspace.insertPane(codex, axis: .columns))
        XCTAssertTrue(workspace.insertPane(claude, axis: .rows))
        XCTAssertTrue(workspace.removePane(claude.id))
        let url = root.appendingPathComponent("mixed.json")
        try StateStore.save(SavedState(workspaces: [workspace], selectedID: workspace.id), to: url)
        var restored = try StateStore.load(from: url).workspaces[0]
        let retained = try XCTUnwrap(restored.retainedPanes?.first)
        XCTAssertEqual(retained.mode, .claude)
        XCTAssertTrue(restored.insertPane(retained, axis: .rows))
        try manager.validate(retained)
        XCTAssertEqual(try String(contentsOfFile: retained.directory + "/shared.txt"), "Claude changes")
        XCTAssertEqual(try manager.git(retained.directory, ["diff", "--cached", "--name-only"]), "shared.txt")
        XCTAssertThrowsError(try manager.create(for: Pane(title: "shell", directory: repo.path, mode: .shell)))
    }

    func testClosePersistRestoreKeepsUncommittedWorkAndLegacyLayoutLoads() throws {
        try commitFixture()
        let isolated = try manager.create(for: pane())
        try "keep me".write(toFile: isolated.directory + "/shared.txt", atomically: true, encoding: .utf8)
        var workspace = Workspace(name: "Test", directory: repo.path)
        XCTAssertTrue(workspace.insertPane(isolated, axis: .columns))
        XCTAssertTrue(workspace.removePane(isolated.id))
        let stateURL = root.appendingPathComponent("state.json")
        try StateStore.save(SavedState(workspaces: [workspace], selectedID: workspace.id), to: stateURL)
        var restored = try StateStore.load(from: stateURL).workspaces[0]
        let retained = try XCTUnwrap(restored.retainedPanes?.first)
        XCTAssertTrue(restored.insertPane(retained, axis: .columns))
        XCTAssertTrue(restored.retainedPanes!.isEmpty)
        try manager.validate(retained)
        XCTAssertEqual(try String(contentsOfFile: retained.directory + "/shared.txt"), "keep me")
        let shared = Workspace(name: "Old", directory: repo.path)
        let old = SavedState(workspaces: [shared], selectedID: shared.id)
        let oldData = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("worktree"))
        XCTAssertTrue(try JSONDecoder().decode(SavedState.self, from: oldData).isValid)
    }

    func testNonGitAndUnbornRepositoryFailWithoutSharedFallback() throws {
        XCTAssertThrowsError(try manager.create(for: pane()))
        let other = root.appendingPathComponent("not-git")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        XCTAssertThrowsError(try manager.create(for: pane(directory: other.path)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.storageURL.path))
    }

    func testSubdirectoryAndMissingWorktreeValidation() throws {
        try commitFixture()
        let isolated = try manager.create(for: pane(directory: repo.appendingPathComponent("sub dir").path))
        XCTAssertTrue(isolated.directory.hasSuffix("/sub dir"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.directory + "/file.txt"))
        let rootPath = try XCTUnwrap(isolated.worktree?.rootDirectory)
        let moved = rootPath + "-moved"
        try FileManager.default.moveItem(atPath: rootPath, toPath: moved)
        XCTAssertThrowsError(try manager.validate(isolated))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved + "/sub dir/file.txt"))
    }

    func testCreationDoesNotRunRepoHooksOrOverwriteExistingCheckout() throws {
        try commitFixture()
        let marker = repo.appendingPathComponent("HOOK_RAN")
        let hook = repo.appendingPathComponent(".git/hooks/post-checkout")
        try "#!/bin/sh\ntouch HOOK_RAN\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let original = pane()
        let isolated = try manager.create(for: original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.directory + "/HOOK_RAN"))
        try "preserved".write(toFile: isolated.directory + "/shared.txt", atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try manager.create(for: original))
        XCTAssertEqual(try String(contentsOfFile: isolated.directory + "/shared.txt"), "preserved")
        var wrong = isolated; wrong.directory = repo.path
        XCTAssertThrowsError(try manager.validate(wrong))
    }
}
