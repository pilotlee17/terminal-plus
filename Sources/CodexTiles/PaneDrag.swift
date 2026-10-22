import AppKit
import TilesCore

/// Capture only the header background and labels; buttons keep their normal actions.
final class PaneDragHeader: NSView {
    var onFocus: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onBegin: () -> Bool = { false }
    var onUpdate: (NSPoint) -> Void = { _ in }
    var onEnd: (NSPoint?) -> Void = { _ in }
    private var start: NSPoint?
    private var dragging = false
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            if view is NSButton { return hit }
            candidate = view.superview
        }
        return self
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { start = nil; onFocus(); onDoubleClick(); return }
        start = event.locationInWindow; dragging = false; onFocus()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        if !dragging {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 5 else { return }
            guard onBegin() else { self.start = nil; return }
            dragging = true; window?.makeFirstResponder(self)
        }
        NSCursor.closedHand.set(); onUpdate(event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging; start = nil; dragging = false
        NSCursor.arrow.set()
        if wasDragging { onEnd(event.locationInWindow) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, dragging {
            dragging = false; start = nil; NSCursor.arrow.set(); onEnd(nil)
        }
    }
}

final class PaneDropPreview: NSView {
    var preview: NSRect? { didSet { needsDisplay = true } }
    var placement: PanePlacement = .center
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    // This view uses AppKit's unflipped coordinates: top is maxY.
    static func placement(at point: NSPoint, in rect: NSRect) -> PanePlacement {
        let x = (point.x - rect.minX) / max(1, rect.width)
        let y = (point.y - rect.minY) / max(1, rect.height)
        let edges: [(CGFloat, PanePlacement)] = [(x, .left), (1 - x, .right), (y, .bottom), (1 - y, .top)]
        let closest = edges.min { $0.0 < $1.0 }!
        return closest.0 < 0.25 ? closest.1 : .center
    }
    static func region(_ rect: NSRect, placement: PanePlacement) -> NSRect {
        switch placement {
        case .center: return rect
        case .left: return NSRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right: return NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top: return NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        case .bottom: return NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let preview else { return }
        let path = NSBezierPath(roundedRect: preview.insetBy(dx: 3, dy: 3), xRadius: 9, yRadius: 9)
        Theme.accent.withAlphaComponent(0.2).setFill(); path.fill()
        Theme.accent.setStroke(); path.lineWidth = 3; path.stroke()
        let text = placement == .center ? "交换位置" : "移到这里"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: Theme.text]
        let size = (text as NSString).size(withAttributes: attributes)
        if preview.width > size.width + 16, preview.height > size.height + 16 {
            (text as NSString).draw(at: NSPoint(x: preview.midX - size.width / 2, y: preview.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
