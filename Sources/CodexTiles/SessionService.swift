import Foundation
import TilesCore
import Darwin

struct SessionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class SessionService {
    let environment: [String: String]
    let tmux: String?
    let queue = DispatchQueue(label: "app.codextiles.sessions")
    let socket: String
    var baseArguments: [String] { ["-L", socket, "-f", "/dev/null"] }

    init(socket: String = SessionArguments.socket) {
        self.socket = socket
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = (env["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        paths += ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            paths += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { nvm + "/" + $0 + "/bin" }
        }
        var seen = Set<String>()
        paths = paths.filter { seen.insert($0).inserted }
        env["PATH"] = paths.joined(separator: ":")
        env["TERM"] = "xterm-256color"; env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        for key in ["TMUX", "TMUX_PANE", "DYLD_INSERT_LIBRARIES", "LD_PRELOAD"] { env.removeValue(forKey: key) }
        environment = env
        func find(_ name: String) -> String? { paths.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) } }
        tmux = find("tmux")
    }

    // Only tmux control commands run here. Interactive programs live in tmux's PTY.
    func run(_ arguments: [String]) throws -> String {
        guard let tmux else { throw SessionFailure(message: "没有找到 tmux。请在终端执行 brew install tmux，然后重开应用。") }
        return try CommandRunner.run(executable: tmux, arguments: baseArguments + arguments, environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepare(_ pane: Pane, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result {
                if (try? self.run(["has-session", "-t", "=" + pane.sessionName])) != nil { return }
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: pane.directory, isDirectory: &directory), directory.boolValue else {
                    throw SessionFailure(message: "终端目录不存在：\(pane.directory)")
                }
                let args = SessionArguments.create(pane: Pane(id: pane.id, title: pane.title, directory: pane.directory), executable: "/bin/zsh")
                _ = try self.run(Array(args.dropFirst(SessionArguments.base().count)))
                _ = try self.run(["set-option", "-t", pane.sessionName, "status", "off"])
                _ = try self.run(["set-option", "-t", pane.sessionName, "mouse", "on"])
                _ = try self.run(["set-option", "-t", pane.sessionName, "history-limit", "20000"])
                _ = try self.run(["set-option", "-t", pane.sessionName, "remain-on-exit", "on"])
                _ = try self.run(["set-option", "-t", pane.sessionName, "allow-passthrough", "on"])
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func kill(_ pane: Pane, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { _ = try self.run(["kill-session", "-t", "=" + pane.sessionName]) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func statuses(completion: @escaping ([String: (status: String, directory: String)]) -> Void) {
        queue.async {
            let output = try? self.run(["list-panes", "-a", "-F", "#{session_name}\t#{pane_dead}\t#{pane_current_command}\t#{pane_current_path}"])
            var result: [String: (status: String, directory: String)] = [:]
            for row in (output ?? "").split(separator: "\n") {
                let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if fields.count == 4 { result[fields[0]] = (fields[1] == "1" ? "进程已退出" : fields[2] + " · 运行中", fields[3]) }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func redraw(_ pane: Pane) {
        queue.async {
            guard let clients = try? self.run(["list-clients", "-t", "=" + pane.sessionName, "-F", "#{client_tty}"]) else { return }
            for tty in clients.split(separator: "\n") {
                _ = try? self.run(["refresh-client", "-t", String(tty)])
            }
        }
    }
}
