import Foundation

public struct WorktreeInfo: Codable, Equatable {
    public let sourceDirectory: String
    public let rootDirectory: String
    public let commonGitDirectory: String
    public let branch: String
    public let baseCommit: String
    public let sourceWasDirty: Bool
    public var isValid: Bool {
        sourceDirectory.hasPrefix("/") && rootDirectory.hasPrefix("/") && commonGitDirectory.hasPrefix("/")
            && branch.hasPrefix("codex/tiles-") && [40, 64].contains(baseCommit.count)
            && baseCommit.allSatisfy { $0.isHexDigit }
    }
}

public struct WorktreeFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public final class WorktreeManager {
    public let storageURL: URL
    public init(storageURL: URL) { self.storageURL = storageURL.standardizedFileURL.resolvingSymlinksInPath() }
    public static var defaultStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Tiles/Worktrees", isDirectory: true)
    }

    // Fixed executable and argument arrays: no shell evaluation of paths or branch names.
    // Hooks are disabled only for these app-managed Git operations, never in repository config.
    @discardableResult func git(_ directory: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> String {
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("GIT_") || key.hasPrefix("DYLD_") || key == "LD_PRELOAD" { environment.removeValue(forKey: key) }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        let value: String
        do {
            value = try CommandRunner.run(executable: "/usr/bin/git", arguments: ["-c", "core.hooksPath=/dev/null", "-C", directory] + arguments,
                                          environment: environment, timeout: timeout, outputLimit: 65536)
        } catch { throw WorktreeFailure("Git 操作失败：\(error.localizedDescription)") }
        // Git appends one newline to these plumbing responses. Preserve spaces in real paths.
        return value.hasSuffix("\n") ? String(value.dropLast()) : value
    }

    public func create(for original: Pane) throws -> Pane {
        guard original.mode.isAgent, original.worktree == nil else { throw WorktreeFailure("只有新的 Codex 或 Claude Code 面板可以创建隔离目录。") }
        let source = URL(fileURLWithPath: original.directory).standardizedFileURL.resolvingSymlinksInPath()
        guard (try? git(source.path, ["rev-parse", "--is-inside-work-tree"])) == "true" else {
            throw WorktreeFailure("该目录不在 Git 工作区内，无法自动隔离。请在「新建面板」中明确选择「共享目录」，或打开已提交的 Git 项目。")
        }
        let repository = try git(source.path, ["rev-parse", "--show-toplevel"])
        let repo = URL(fileURLWithPath: repository).standardizedFileURL.resolvingSymlinksInPath()
        guard let commit = try? git(source.path, ["rev-parse", "--verify", "HEAD^{commit}"]) else {
            throw WorktreeFailure("仓库还没有提交。请先完成首次提交，再创建隔离 AI 面板。应用不会替你提交现有文件。")
        }
        guard !storageURL.path.hasPrefix(repo.path + "/"), storageURL.path != repo.path else {
            throw WorktreeFailure("隔离目录不能位于源仓库内部。请选择其他 Git 项目。")
        }
        let relative: String
        if source.path == repo.path { relative = "" }
        else if source.path.hasPrefix(repo.path + "/") { relative = String(source.path.dropFirst(repo.path.count + 1)) }
        else { throw WorktreeFailure("所选目录不属于解析出的 Git 项目。") }
        if !relative.isEmpty, (try? git(repo.path, ["cat-file", "-t", commit + ":" + relative])) != "tree" {
            throw WorktreeFailure("所选子目录尚未包含在 HEAD 提交中。请先提交该目录，或打开仓库根目录。")
        }
        let common = try git(repo.path, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
        let dirty = try !git(repo.path, ["status", "--porcelain=v1", "--untracked-files=normal"]).isEmpty
        let key = original.id.uuidString.lowercased()
        let destination = storageURL.appendingPathComponent(key, isDirectory: true)
        let branch = "codex/tiles-" + key
        let manifest = storageURL.appendingPathComponent(key + ".json")
        guard !FileManager.default.fileExists(atPath: destination.path), !FileManager.default.fileExists(atPath: manifest.path) else {
            throw WorktreeFailure("该隔离目录已存在。已有内容已保留，请从保留的隔离工作区恢复。")
        }
        var pane = original
        pane.worktree = WorktreeInfo(sourceDirectory: repo.path, rootDirectory: destination.path,
                                     commonGitDirectory: URL(fileURLWithPath: common).resolvingSymlinksInPath().path,
                                     branch: branch, baseCommit: commit, sourceWasDirty: dirty)
        pane.directory = relative.isEmpty ? destination.path : destination.appendingPathComponent(relative).path
        // Persist intent before Git mutates anything. A crash/failure never erases work.
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pane).write(to: manifest, options: .withoutOverwriting)
        do {
            try git(repo.path, ["worktree", "add", "-b", branch, "--", destination.path, commit], timeout: 120)
            try validate(pane)
        } catch {
            throw WorktreeFailure("创建隔离目录未完成，不会启动 AI 工具。已保留记录和可能生成的文件：\(destination.path)\n\(error.localizedDescription)")
        }
        return pane
    }

    public func validate(_ pane: Pane) throws {
        guard let info = pane.worktree, info.isValid else { throw WorktreeFailure("隔离记录无效，未启动 AI 工具。") }
        let expected = storageURL.appendingPathComponent(pane.id.uuidString.lowercased()).path
        guard info.rootDirectory == expected,
              URL(fileURLWithPath: info.rootDirectory).resolvingSymlinksInPath().path == expected,
              pane.directory == expected || pane.directory.hasPrefix(expected + "/") else {
            throw WorktreeFailure("隔离路径与记录不一致，未启动 AI 工具。")
        }
        let actualCWD = URL(fileURLWithPath: pane.directory).standardizedFileURL.resolvingSymlinksInPath().path
        guard actualCWD == expected || actualCWD.hasPrefix(expected + "/"),
              let top = try? git(pane.directory, ["rev-parse", "--show-toplevel"]),
              URL(fileURLWithPath: top).standardizedFileURL.resolvingSymlinksInPath().path == expected,
              let common = try? git(pane.directory, ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
              URL(fileURLWithPath: common).resolvingSymlinksInPath().path == info.commonGitDirectory else {
            throw WorktreeFailure("隔离目录缺失、已移动或属于其他仓库。原文件不会被重建或覆盖：\(expected)")
        }
        // A branch change is allowed: the dedicated working directory remains isolated.
    }
}
