import Foundation

public enum PaneMode: String, Codable, CaseIterable {
    case codex, claude, shell
    public var displayName: String {
        switch self { case .codex: return "Codex"; case .claude: return "Claude Code"; case .shell: return "普通终端" }
    }
    public var isAgent: Bool { self != .shell }
    public var symbol: String {
        switch self { case .codex: return "✳"; case .claude: return "✦"; case .shell: return "›_" }
    }
}
public enum SplitAxis: String, Codable { case columns, rows }

public struct Pane: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var directory: String
    public var mode: PaneMode
    public var worktree: WorktreeInfo?
    public var sessionName: String { "tiles-" + id.uuidString.lowercased() }
    public init(id: UUID = UUID(), title: String, directory: String, mode: PaneMode = .shell) {
        self.id = id; self.title = title; self.directory = directory; self.mode = mode
    }
}

public indirect enum Layout: Codable, Equatable {
    case pane(UUID)
    case split(UUID, SplitAxis, Double, Layout, Layout)

    public var hasValidStructure: Bool {
        var splits = Set<UUID>(), panes = Set<UUID>()
        func check(_ node: Layout) -> Bool {
            switch node {
            case .pane(let id): return panes.insert(id).inserted
            case .split(let id, _, let ratio, let a, let b):
                return splits.insert(id).inserted && ratio.isFinite && ratio > 0 && ratio < 1 && check(a) && check(b)
            }
        }
        return check(self)
    }

    public var paneIDs: [UUID] {
        switch self {
        case .pane(let id): return [id]
        case .split(_, _, _, let a, let b): return a.paneIDs + b.paneIDs
        }
    }
    public func splitting(_ target: UUID, with newID: UUID, axis: SplitAxis) -> Layout {
        switch self {
        case .pane(let id): return id == target ? .split(UUID(), axis, 0.5, self, .pane(newID)) : self
        case .split(let id, let direction, let ratio, let a, let b):
            return .split(id, direction, ratio, a.splitting(target, with: newID, axis: axis), b.splitting(target, with: newID, axis: axis))
        }
    }
    public func removing(_ target: UUID) -> Layout? {
        switch self {
        case .pane(let id): return id == target ? nil : self
        case .split(let id, let axis, let ratio, let a, let b):
            let left = a.removing(target), right = b.removing(target)
            if let left, let right { return .split(id, axis, ratio, left, right) }
            return left ?? right
        }
    }
    public func settingRatio(_ target: UUID, _ value: Double) -> Layout {
        switch self {
        case .pane: return self
        case .split(let id, let axis, let ratio, let a, let b):
            return .split(id, axis, id == target ? min(0.85, max(0.15, value)) : ratio,
                          a.settingRatio(target, value), b.settingRatio(target, value))
        }
    }
}

public struct Workspace: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var directory: String
    public var panes: [Pane]
    public var layout: Layout
    public var focusedID: UUID
    public var retainedPanes: [Pane]?
    public init(name: String, directory: String) {
        id = UUID(); self.name = name; self.directory = directory
        let pane = Pane(title: "终端 01", directory: directory)
        panes = [pane]; layout = .pane(pane.id); focusedID = pane.id
    }
    public var isValid: Bool {
        let ids = panes.map(\.id)
        return !ids.isEmpty && ids.count <= 8 && Set(ids).count == ids.count
            && layout.hasValidStructure && layout.paneIDs.count == ids.count && Set(layout.paneIDs) == Set(ids)
            && ids.contains(focusedID) && directory.hasPrefix("/")
            && panes.allSatisfy { $0.directory.hasPrefix("/") && ($0.worktree?.isValid ?? true) }
            && (retainedPanes ?? []).allSatisfy { $0.worktree?.isValid == true }
    }
    @discardableResult public mutating func addPane(mode: PaneMode, axis: SplitAxis) -> Pane? {
        guard panes.count < 8 else { return nil }
        let pane = Pane(title: "\(mode.displayName) \(String(format: "%02d", panes.count + 1))", directory: directory, mode: mode)
        _ = insertPane(pane, axis: axis)
        return pane
    }
    @discardableResult public mutating func insertPane(_ pane: Pane, axis: SplitAxis) -> Bool {
        guard panes.count < 8, !panes.contains(where: { $0.id == pane.id }) else { return false }
        layout = layout.splitting(focusedID, with: pane.id, axis: axis)
        panes.append(pane); focusedID = pane.id
        retainedPanes?.removeAll { $0.id == pane.id }
        return true
    }
    @discardableResult public mutating func removePane(_ id: UUID) -> Bool {
        guard panes.count > 1, panes.contains(where: { $0.id == id }), let next = layout.removing(id) else { return false }
        if let pane = panes.first(where: { $0.id == id }), pane.worktree != nil {
            if retainedPanes == nil { retainedPanes = [] }
            retainedPanes?.append(pane)
        }
        layout = next; panes.removeAll { $0.id == id }
        if focusedID == id { focusedID = panes[0].id }
        return true
    }
}

public struct SavedState: Codable {
    public var version = 1
    public var workspaces: [Workspace]
    public var selectedID: UUID
    public init(workspaces: [Workspace], selectedID: UUID) { self.workspaces = workspaces; self.selectedID = selectedID }
    public var isValid: Bool {
        version == 1 && !workspaces.isEmpty && workspaces.count <= 32
            && Set(workspaces.map(\.id)).count == workspaces.count
            && Set(workspaces.flatMap { $0.panes.map(\.id) }).count == workspaces.flatMap(\.panes).count
            && workspaces.allSatisfy(\.isValid) && workspaces.contains { $0.id == selectedID }
    }
}

public enum StateStore {
    public static func load(from url: URL) throws -> SavedState {
        let value = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        guard value.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    public static func save(_ value: SavedState, to url: URL) throws {
        guard value.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public enum SessionArguments {
    public static let socket = "codex-tiles"
    public static func base() -> [String] { ["-L", socket, "-f", "/dev/null"] }
    public static func create(pane: Pane, executable: String) -> [String] {
        // Multiple command arguments make tmux use execvp, never sh -c.
        let command = pane.mode == .shell ? [executable, "-l"] : ["/usr/bin/env", executable]
        return base() + ["new-session", "-d", "-s", pane.sessionName, "-c", pane.directory, "-x", "120", "-y", "36"] + command
    }
}
