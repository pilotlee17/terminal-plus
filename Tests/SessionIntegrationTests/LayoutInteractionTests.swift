import XCTest
import AppKit
import TilesCore
@testable import CodexTiles

final class LayoutInteractionTests: XCTestCase {
    func testSplitUsesUsableSpaceAndEnforcesMinimums() {
        let split = TileSplitView(id: UUID(), axis: .columns, ratio: 0.5)
        split.frame = NSRect(x: 0, y: 0, width: 1010, height: 500)
        split.addArrangedSubview(NSView()); split.addArrangedSubview(NSView())
        split.restore()
        XCTAssertEqual(split.subviews[0].frame.width, 500, accuracy: 1)
        XCTAssertEqual(split.splitView(split, constrainMinCoordinate: 0, ofSubviewAt: 0), 280)
        XCTAssertEqual(split.splitView(split, constrainMaxCoordinate: 1000, ofSubviewAt: 0), 720)
        split.firstMinimum.width = 1700; split.secondMinimum.width = 280
        split.frame.size.width = 1990
        XCTAssertLessThanOrEqual(split.splitView(split, constrainMinCoordinate: 0, ofSubviewAt: 0), split.splitView(split, constrainMaxCoordinate: 1990, ofSubviewAt: 0))
        split.frame.size.width = 400
        XCTAssertLessThan(split.splitView(split, constrainMinCoordinate: 0, ofSubviewAt: 0), split.splitView(split, constrainMaxCoordinate: 400, ofSubviewAt: 0))
    }
    func testDoubleClickHeaderFocusesAndZoomsWithoutDragging() {
        let header = PaneDragHeader()
        var focused = false, zoomed = false, dragged = false
        header.onFocus = { focused = true }; header.onDoubleClick = { zoomed = true }
        header.onBegin = { dragged = true; return true }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        header.mouseDown(with: event); header.mouseDragged(with: event); header.mouseUp(with: event)
        XCTAssertTrue(focused); XCTAssertTrue(zoomed); XCTAssertFalse(dragged)
    }
}
