import XCTest
import AppKit
@testable import CodexTiles

final class PaneSelectionTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func testDragSelectionClickToggleAndShiftAddition() {
        let a = UUID(), b = UUID(), c = UUID()
        let overlay = PaneSelectionOverlay(frame: NSRect(x: 0, y: 0, width: 310, height: 200))
        overlay.paneFrames = { [a: NSRect(x: 0, y: 0, width: 100, height: 200), b: NSRect(x: 110, y: 110, width: 200, height: 90), c: NSRect(x: 110, y: 0, width: 200, height: 100)] }
        // Reverse-direction drag across the right column must leave the left terminal alone.
        overlay.mouseDown(with: event(.leftMouseDown, 290, 180))
        overlay.mouseDragged(with: event(.leftMouseDragged, 120, 10))
        overlay.mouseUp(with: event(.leftMouseUp, 120, 10))
        XCTAssertEqual(overlay.selected, [b, c])
        overlay.mouseDown(with: event(.leftMouseDown, 150, 20))
        overlay.mouseUp(with: event(.leftMouseUp, 150, 20))
        XCTAssertEqual(overlay.selected, [b])
        overlay.mouseDown(with: event(.leftMouseDown, 20, 20, shift: true))
        overlay.mouseDragged(with: event(.leftMouseDragged, 80, 80, shift: true))
        overlay.mouseUp(with: event(.leftMouseUp, 80, 80, shift: true))
        XCTAssertEqual(overlay.selected, [a, b])
        overlay.selectAll(nil)
        XCTAssertEqual(overlay.selected, [a, b, c])
    }
    func testLockedSelectionAndEmptyGapDoNotChangeTargets() {
        let id = UUID()
        let overlay = PaneSelectionOverlay(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        overlay.paneFrames = { [id: NSRect(x: 0, y: 0, width: 80, height: 100)] }
        overlay.selected = [id]
        overlay.mouseDown(with: event(.leftMouseDown, 100, 30))
        overlay.mouseUp(with: event(.leftMouseUp, 100, 30))
        XCTAssertEqual(overlay.selected, [id])
        overlay.locked = true
        overlay.mouseDown(with: event(.leftMouseDown, 20, 20))
        overlay.mouseDragged(with: event(.leftMouseDragged, 190, 90))
        overlay.mouseUp(with: event(.leftMouseUp, 190, 90))
        XCTAssertEqual(overlay.selected, [id])
    }
}
