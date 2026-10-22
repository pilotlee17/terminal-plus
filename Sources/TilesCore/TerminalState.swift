import Foundation

/// A single terminal canvas. Legacy workspace records are read only during migration.
public struct TerminalState: Codable {
    public var panes: [Pane]
    public var layout: Layout?
    public var focusedID: UUID?
    public var parked: [Pane]
    public init(directory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        let pane = Pane(title: "终端 01", directory: directory)
        panes = [pane]; layout = .pane(pane.id); focusedID = pane.id; parked = []
    }
    public init(legacy: SavedState) {
        let selected = legacy.workspaces.first { $0.id == legacy.selectedID } ?? legacy.workspaces[0]
        func terminal(_ pane: Pane, index: Int) -> Pane {
            var value = pane; value.mode = .shell; value.worktree = nil
            value.title = String(format: "终端 %02d", index + 1)
            return value
        }
        panes = selected.panes.enumerated().map { terminal($0.element, index: $0.offset) }
        layout = selected.layout; focusedID = selected.focusedID
        var seen = Set(panes.map(\.id))
        let others = legacy.workspaces.filter { $0.id != selected.id }.flatMap(\.panes)
            + legacy.workspaces.flatMap { $0.retainedPanes ?? [] }
        let activeCount = panes.count
        parked = others.filter { seen.insert($0.id).inserted }.enumerated().map { terminal($0.element, index: $0.offset + activeCount) }
    }
    public var isValid: Bool {
        let ids = panes.map(\.id), all = panes + parked
        return panes.count <= 8 && Set(all.map(\.id)).count == all.count
            && all.allSatisfy { $0.mode == .shell && $0.worktree == nil && $0.directory.hasPrefix("/") }
            && (panes.isEmpty ? layout == nil && focusedID == nil :
                layout?.hasValidStructure == true && Set(layout?.paneIDs ?? []) == Set(ids) && layout?.paneIDs.count == ids.count && ids.contains(focusedID ?? UUID()))
    }
    @discardableResult public mutating func insert(_ pane: Pane, axis: SplitAxis) -> Bool {
        guard panes.count < 8, pane.mode == .shell, pane.worktree == nil, !panes.contains(where: { $0.id == pane.id }) else { return false }
        if let focusedID, let layout { self.layout = layout.splitting(focusedID, with: pane.id, axis: axis) }
        else { layout = .pane(pane.id) }
        panes.append(pane); focusedID = pane.id; parked.removeAll { $0.id == pane.id }; return true
    }
    @discardableResult public mutating func remove(_ id: UUID) -> Bool {
        guard panes.contains(where: { $0.id == id }) else { return false }
        let visualOrder = layout?.paneIDs ?? panes.map(\.id)
        let index = visualOrder.firstIndex(of: id) ?? 0
        let neighbor = index + 1 < visualOrder.count ? visualOrder[index + 1] : (index > 0 ? visualOrder[index - 1] : nil)
        panes.removeAll { $0.id == id }; layout = layout?.removing(id)
        if focusedID == id { focusedID = neighbor }
        return true
    }
    public static func load(from url: URL) throws -> TerminalState {
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard result.isValid else { throw CocoaError(.fileReadCorruptFile) }; return result
    }
    public func save(to url: URL) throws {
        guard isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
