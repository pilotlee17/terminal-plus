import Foundation

extension Layout {
    /// Balanced rows keep the reading order while avoiding repeatedly halved slivers.
    public static func tiled(_ ids: [UUID], size: CGSize) -> Layout? {
        guard !ids.isEmpty else { return nil }
        let width = max(1, size.width), height = max(1, size.height)
        let rows = (1...ids.count).min { a, b in
            func score(_ rows: Int) -> Double {
                let columns = Int(ceil(Double(ids.count) / Double(rows)))
                let w = max(1, (width - CGFloat(columns - 1) * 10) / CGFloat(columns))
                let h = max(1, (height - CGFloat(rows - 1) * 10) / CGFloat(rows))
                return pow(log(Double(w / h) / 1.8), 2)
                    + max(0, Double(280 / w - 1)) * 4 + max(0, Double(160 / h - 1)) * 4
            }
            return score(a) < score(b)
        }!
        func combine(_ nodes: [Layout], axis: SplitAxis) -> Layout {
            guard nodes.count > 1 else { return nodes[0] }
            let half = nodes.count / 2
            return .split(UUID(), axis, Double(half) / Double(nodes.count),
                          combine(Array(nodes[..<half]), axis: axis), combine(Array(nodes[half...]), axis: axis))
        }
        var offset = 0
        let rowNodes: [Layout] = (0..<rows).map { row in
            let count = ids.count / rows + (row < ids.count % rows ? 1 : 0)
            defer { offset += count }
            return combine(ids[offset..<offset + count].map { .pane($0) }, axis: .columns)
        }
        return combine(rowNodes, axis: .rows)
    }

    public var minimumSize: CGSize {
        switch self {
        case .pane: return CGSize(width: 280, height: 160)
        case .split(_, let axis, _, let a, let b):
            let x = a.minimumSize, y = b.minimumSize
            return axis == .columns
                ? CGSize(width: x.width + y.width + 10, height: max(x.height, y.height))
                : CGSize(width: max(x.width, y.width), height: x.height + y.height + 10)
        }
    }
}
