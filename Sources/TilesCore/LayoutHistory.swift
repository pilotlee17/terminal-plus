import Foundation

/// Only layout changes are undoable. Adding/removing sessions clears this history.
public struct LayoutHistory {
    private var past: [Layout] = []
    private var future: [Layout] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func record(_ previous: Layout, current: Layout) {
        guard previous != current else { return }
        guard Set(previous.paneIDs) == Set(current.paneIDs) else { clear(); return }
        past.append(previous); if past.count > 30 { past.removeFirst() }; future.removeAll()
    }
    public mutating func undo(current: Layout) -> Layout? {
        guard let previous = past.last, Set(previous.paneIDs) == Set(current.paneIDs) else { clear(); return nil }
        past.removeLast(); future.append(current); return previous
    }
    public mutating func redo(current: Layout) -> Layout? {
        guard let next = future.last, Set(next.paneIDs) == Set(current.paneIDs) else { clear(); return nil }
        future.removeLast(); past.append(current); return next
    }
    public mutating func clear() { past.removeAll(); future.removeAll() }
}
