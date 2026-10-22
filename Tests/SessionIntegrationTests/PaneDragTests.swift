import XCTest
import AppKit
import TilesCore
@testable import CodexTiles

final class PaneDragTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func testDropZonesAndPreviewAgree() {
        let rect = NSRect(x: 100, y: 200, width: 400, height: 200)
        let samples: [(NSPoint, PanePlacement)] = [(.init(x: 300, y: 300), .center), (.init(x: 110, y: 300), .left), (.init(x: 490, y: 300), .right), (.init(x: 300, y: 390), .top), (.init(x: 300, y: 210), .bottom)]
        for (point, placement) in samples {
            XCTAssertEqual(PaneDropPreview.placement(at: point, in: rect), placement)
            XCTAssertTrue(PaneDropPreview.region(rect, placement: placement).contains(point))
        }
    }
    func testDragThresholdCancelAndDisabledMode() {
        let header = PaneDragHeader(frame: .init(x: 0, y: 0, width: 400, height: 42))
        var began = 0, ended = 0, cancelled = false
        header.onBegin = { began += 1; return true }
        header.onEnd = { point in ended += 1; cancelled = point == nil }
        header.mouseDown(with: event(.leftMouseDown, 20, 20))
        header.mouseDragged(with: event(.leftMouseDragged, 22, 20))
        header.mouseUp(with: event(.leftMouseUp, 22, 20))
        XCTAssertEqual(began, 0); XCTAssertEqual(ended, 0)
        header.mouseDown(with: event(.leftMouseDown, 20, 20))
        header.mouseDragged(with: event(.leftMouseDragged, 80, 30))
        header.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!)
        header.mouseUp(with: event(.leftMouseUp, 90, 30))
        XCTAssertEqual(began, 1); XCTAssertEqual(ended, 1); XCTAssertTrue(cancelled)
        header.onBegin = { false }
        header.mouseDown(with: event(.leftMouseDown, 20, 20))
        header.mouseDragged(with: event(.leftMouseDragged, 80, 30))
        header.mouseUp(with: event(.leftMouseUp, 90, 30))
        XCTAssertEqual(ended, 1)
    }
    func testHeaderLabelsDragButButtonsStillReceiveClicks() {
        let header = PaneDragHeader(frame: .init(x: 0, y: 0, width: 400, height: 42))
        let text = NSTextField(labelWithString: "terminal")
        text.frame = .init(x: 10, y: 0, width: 100, height: 42)
        let button = NSButton(frame: .init(x: 300, y: 0, width: 90, height: 42))
        header.addSubview(text); header.addSubview(button)
        XCTAssertTrue(header.hitTest(.init(x: 20, y: 20)) === header)
        XCTAssertTrue(header.hitTest(.init(x: 320, y: 20)) === button)
    }
}
