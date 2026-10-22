import Foundation

public enum PanePlacement: CaseIterable {
    case center, left, right, top, bottom
}

extension Layout {
    public func rearranging(_ source: UUID, relativeTo target: UUID, placement: PanePlacement) -> Layout {
        guard source != target, paneIDs.contains(source), paneIDs.contains(target) else { return self }
        if placement == .center {
            func swap(_ node: Layout) -> Layout {
                switch node {
                case .pane(let id): return .pane(id == source ? target : id == target ? source : id)
                case .split(let id, let axis, let ratio, let a, let b):
                    return .split(id, axis, ratio, swap(a), swap(b))
                }
            }
            return swap(self)
        }
        guard let remainder = removing(source) else { return self }
        func insert(_ node: Layout) -> Layout {
            switch node {
            case .pane(let id):
                guard id == target else { return node }
                let first = placement == .left || placement == .top
                return .split(UUID(), placement == .left || placement == .right ? .columns : .rows, 0.5,
                              .pane(first ? source : target), .pane(first ? target : source))
            case .split(let id, let axis, let ratio, let a, let b):
                return .split(id, axis, ratio, insert(a), insert(b))
            }
        }
        return insert(remainder)
    }
}

extension TerminalState {
    @discardableResult public mutating func move(_ source: UUID, relativeTo target: UUID, placement: PanePlacement) -> Bool {
        guard source != target, let layout, layout.paneIDs.contains(source), layout.paneIDs.contains(target) else { return false }
        self.layout = layout.rearranging(source, relativeTo: target, placement: placement)
        focusedID = source
        return true
    }
}
