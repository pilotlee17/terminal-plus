import Foundation
import Darwin

/// Short control commands must finish when their process exits, even if a PTY
/// or descendant inherited the output pipe and keeps its write end open.
public struct CommandFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public enum CommandRunner {
    public static func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval = 4, outputLimit: Int = 32768) throws -> String {
        let process = Process(), output = Pipe()
        let reader = output.fileHandleForReading
        let writer = output.fileHandleForWriting
        defer { try? reader.close(); try? writer.close() }
        let fd = reader.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1,
              fcntl(fd, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(writer.fileDescriptor, F_SETFD, FD_CLOEXEC) != -1 else {
            throw CommandFailure(message: "无法配置命令输出")
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = output
        try process.run()
        try? writer.close()
        var captured = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        func drain() {
            // Bound each pass so continuous output cannot starve the deadline.
            for _ in 0..<8 {
                let count = Darwin.read(fd, &buffer, buffer.count)
                guard count > 0 else { break }
                captured.append(contentsOf: buffer.prefix(min(count, max(0, outputLimit - captured.count))))
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var timedOut = false
        while process.isRunning {
            drain()
            if ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = true
                process.terminate()
                let grace = ProcessInfo.processInfo.systemUptime + 0.2
                while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                    drain(); Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Never wait for pipe EOF: unrelated long-lived children can own it.
        drain()
        if timedOut { throw CommandFailure(message: "命令执行超时，请重试。") }
        let text = String(decoding: captured, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CommandFailure(message: text.isEmpty ? "命令执行失败" : text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}
