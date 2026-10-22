import AppKit

/// Installed only in selection mode, so terminal text selection is unaffected.
final class PaneSelectionOverlay: NSView {
    var paneFrames: () -> [UUID: NSRect] = { [:] }
    var onChange: (Set<UUID>) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onClose: () -> Void = {}
    var selected = Set<UUID>() { didSet { needsDisplay = true } }
    var locked = false
    private var start: NSPoint?
    private var marquee: NSRect?
    private var initial = Set<UUID>()
    private var additive = false
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        guard !locked else { return }
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        initial = selected; additive = event.modifierFlags.contains(.shift)
    }
    override func mouseDragged(with event: NSEvent) {
        guard !locked, let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        guard abs(end.x - start.x) + abs(end.y - start.y) > 4 else { return }
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
        marquee = rect
        selected = Set(paneFrames().filter { $0.value.intersects(rect) }.map(\.key)).union(additive ? initial : [])
        onChange(selected)
    }
    override func mouseUp(with event: NSEvent) {
        guard !locked, let start else { return }
        if marquee == nil, let id = paneFrames().first(where: { $0.value.contains(start) })?.key {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            onChange(selected)
        }
        self.start = nil; marquee = nil; needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() }
        else if event.keyCode == 51 || event.keyCode == 117 { onClose() }
        // Other keys are intentionally not forwarded to a terminal in selection mode.
    }
    override func selectAll(_ sender: Any?) {
        guard !locked else { return }; selected = Set(paneFrames().keys); onChange(selected)
    }
    override func draw(_ dirtyRect: NSRect) {
        for (id, frame) in paneFrames() {
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            if selected.contains(id) {
                Theme.accent.withAlphaComponent(0.14).setFill(); path.fill()
                Theme.accent.setStroke(); path.lineWidth = 3; path.stroke()
                let badge = NSRect(x: frame.maxX - 34, y: frame.maxY - 34, width: 24, height: 24)
                Theme.accent.setFill(); NSBezierPath(ovalIn: badge).fill()
                ("✓" as NSString).draw(at: NSPoint(x: badge.minX + 5, y: badge.minY + 2), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: Theme.background])
            } else { NSColor.black.withAlphaComponent(0.16).setFill(); path.fill() }
        }
        if let marquee {
            Theme.accent.withAlphaComponent(0.18).setFill(); marquee.fill()
            Theme.accent.setStroke(); let path = NSBezierPath(rect: marquee); path.lineWidth = 1.5; path.stroke()
        }
    }
}
