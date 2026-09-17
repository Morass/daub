import CoreGraphics
import XCTest
@testable import DaubCore

final class BitmapTests: XCTestCase {
    func testStartsOpaqueWhiteWhenFilled() {
        let b = Bitmap(width: 4, height: 3, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(b.pixel(x: 0, y: 0), RGBA(r: 255, g: 255, b: 255, a: 255))
        XCTAssertEqual(b.pixel(x: 3, y: 2), RGBA(r: 255, g: 255, b: 255, a: 255))
    }

    func testOutOfBoundsAccessIsSafe() {
        let b = Bitmap(width: 2, height: 2)
        b.setPixel(x: -1, y: 5, to: RGBA(r: 1, g: 2, b: 3))
        XCTAssertEqual(b.pixel(x: 99, y: 99).a, 0, "reads outside the canvas report empty, not garbage")
    }

    /// Canvas resize must anchor top-left even though CoreGraphics counts y upward.
    func testResizeAnchorsTopLeft() {
        let b = Bitmap(width: 4, height: 4, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let mark = RGBA(r: 255, g: 0, b: 0)
        b.setPixel(x: 0, y: 3, to: mark)                  // top-left pixel
        let grown = b.resized(to: 8, 8, fill: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(grown.pixel(x: 0, y: 7), mark, "the marked pixel stayed at the top-left")
        XCTAssertEqual(grown.pixel(x: 7, y: 0).b, 255, "new area took the fill colour")
    }
}

final class FloodFillTests: XCTestCase {
    private func canvas() -> Bitmap {
        Bitmap(width: 16, height: 16, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }

    func testFillsEnclosedRegionOnly() {
        let b = canvas()
        let wall = RGBA(r: 0, g: 0, b: 0)
        for i in 0..<16 { b.setPixel(x: 8, y: i, to: wall) }   // vertical divider

        let red = RGBA(r: 255, g: 0, b: 0)
        let dirty = FloodFill.fill(b, x: 2, y: 2, with: red)
        XCTAssertNotNil(dirty)
        XCTAssertEqual(b.pixel(x: 0, y: 0), red)
        XCTAssertEqual(b.pixel(x: 7, y: 15), red)
        XCTAssertEqual(b.pixel(x: 8, y: 5), wall, "the wall is untouched")
        XCTAssertEqual(b.pixel(x: 9, y: 5).r, 255)
        XCTAssertEqual(b.pixel(x: 9, y: 5).g, 255, "the far side stayed white")
    }

    func testFillingWithTheSameColourIsANoOp() {
        let b = canvas()
        XCTAssertNil(FloodFill.fill(b, x: 4, y: 4, with: RGBA(r: 255, g: 255, b: 255)))
    }

    /// A replacement colour inside the tolerance band re-matches the seed; without a
    /// visited set this spins forever. This test is the reason that set exists.
    func testToleranceNearOwnColourTerminates() {
        let b = canvas()
        let almostWhite = RGBA(r: 250, g: 250, b: 250)
        let dirty = FloodFill.fill(b, x: 4, y: 4, with: almostWhite, tolerance: 32)
        XCTAssertNotNil(dirty)
        XCTAssertEqual(b.pixel(x: 0, y: 0), almostWhite)
    }

    func testOutsideSeedDoesNothing() {
        let b = canvas()
        XCTAssertNil(FloodFill.fill(b, x: -1, y: 0, with: RGBA(r: 0, g: 0, b: 0)))
    }
}

final class RasterTests: XCTestCase {
    func testLineHitsBothEndpointsAndTheMiddle() {
        let b = Bitmap(width: 16, height: 16, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let black = RGBA(r: 0, g: 0, b: 0)
        Raster.line(b, from: (0, 0), to: (10, 10), size: 1, color: black)
        XCTAssertEqual(b.pixel(x: 0, y: 0), black)
        XCTAssertEqual(b.pixel(x: 5, y: 5), black)
        XCTAssertEqual(b.pixel(x: 10, y: 10), black)
        XCTAssertNotEqual(b.pixel(x: 5, y: 9), black)
    }

    func testStampIsCentredAndHardEdged() {
        let b = Bitmap(width: 16, height: 16, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let black = RGBA(r: 0, g: 0, b: 0)
        Raster.stamp(b, x: 8, y: 8, size: 3, color: black)
        for dy in -1...1 {
            for dx in -1...1 {
                XCTAssertEqual(b.pixel(x: 8 + dx, y: 8 + dy), black)
            }
        }
        XCTAssertNotEqual(b.pixel(x: 10, y: 8), black, "no anti-aliased fringe")
    }

    func testSprayStaysInsideItsRadius() {
        let b = Bitmap(width: 64, height: 64, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        var rng = SystemRandomNumberGenerator()
        Raster.spray(b, x: 32, y: 32, radius: 5, density: 400, color: RGBA(r: 0, g: 0, b: 0), using: &rng)
        for y in 0..<64 {
            for x in 0..<64 where b.pixel(x: x, y: y).r == 0 {
                let d = ((x - 32) * (x - 32) + (y - 32) * (y - 32))
                XCTAssertLessThanOrEqual(d, 6 * 6, "pixel (\(x),\(y)) escaped the radius")
            }
        }
    }
}

final class ShapesTests: XCTestCase {
    func testFilledRectanglePaintsItsInterior() {
        let b = Bitmap(width: 32, height: 32, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        Shapes.draw(.rectangle, in: b.context,
                    from: CGPoint(x: 8, y: 8), to: CGPoint(x: 24, y: 24),
                    stroke: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                    fill: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
                    style: .filled, lineWidth: 1, antialias: false)
        XCTAssertEqual(b.pixel(x: 16, y: 16), RGBA(r: 0, g: 0, b: 255))
        XCTAssertEqual(b.pixel(x: 2, y: 2), RGBA(r: 255, g: 255, b: 255))
    }

    func testOutlineLeavesTheInteriorAlone() {
        let b = Bitmap(width: 32, height: 32, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        Shapes.draw(.ellipse, in: b.context,
                    from: CGPoint(x: 4, y: 4), to: CGPoint(x: 28, y: 28),
                    stroke: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                    fill: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
                    style: .outline, lineWidth: 2, antialias: false)
        XCTAssertEqual(b.pixel(x: 16, y: 16), RGBA(r: 255, g: 255, b: 255))
        XCTAssertEqual(b.pixel(x: 16, y: 27).r, 0, "the rim was stroked")
    }
}

final class UndoHistoryTests: XCTestCase {
    private func image(_ value: UInt8) -> CGImage {
        let b = Bitmap(width: 2, height: 2,
                       fill: CGColor(srgbRed: CGFloat(value) / 255, green: 0, blue: 0, alpha: 1))
        return b.makeImage()!
    }

    func testUndoRedoRoundTrip() {
        let h = UndoHistory(limit: 4)
        XCTAssertFalse(h.canUndo)
        h.record(image(10))
        XCTAssertTrue(h.canUndo)
        let restored = h.undo(current: image(20))
        XCTAssertNotNil(restored)
        XCTAssertTrue(h.canRedo)
        XCTAssertNotNil(h.redo(current: image(10)))
    }

    func testRecordingDropsTheRedoBranch() {
        let h = UndoHistory()
        h.record(image(1))
        _ = h.undo(current: image(2))
        XCTAssertTrue(h.canRedo)
        h.record(image(3))
        XCTAssertFalse(h.canRedo, "a new edit after undo abandons the redo branch")
    }

    func testHonoursItsLimit() {
        let h = UndoHistory(limit: 3)
        for i in 0..<10 { h.record(image(UInt8(i))) }
        XCTAssertEqual(h.depth, 3)
    }
}

/// Regression: the raster tools (pencil, fill) address memory directly while the brush and
/// shape tools go through CoreGraphics, whose origin is bottom-left. When `pixel()` indexed
/// memory top-down instead, a pencil stroke landed mirrored against an identical brush
/// stroke. These tests pin the two spaces together.
final class CoordinateSpaceTests: XCTestCase {
    func testCoreGraphicsAndRasterAgreeOnUp() {
        let b = Bitmap(width: 16, height: 16, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        // Fill the upper half in CoreGraphics coordinates (y = 8...16).
        b.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        b.context.fill(CGRect(x: 0, y: 8, width: 16, height: 8))

        XCTAssertEqual(b.pixel(x: 4, y: 12).r, 0, "pixel(y:12) must be inside the CG-filled upper half")
        XCTAssertEqual(b.pixel(x: 4, y: 2).r, 255, "pixel(y:2) must still be the untouched lower half")
    }

    func testRasterWriteIsVisibleToCoreGraphicsAtTheSamePlace() {
        let b = Bitmap(width: 8, height: 8, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        Raster.stamp(b, x: 1, y: 7, size: 1, color: RGBA(r: 0, g: 0, b: 0))   // top-left corner
        let image = b.makeImage()!

        // Re-draw into a fresh bitmap; the mark must survive at the same coordinates.
        let copy = Bitmap(width: 8, height: 8)
        copy.replace(with: image)
        XCTAssertEqual(copy.pixel(x: 1, y: 7).r, 0)
        XCTAssertEqual(copy.pixel(x: 1, y: 0).r, 255)
    }

    func testFloodFillSeedMatchesRasterCoordinates() {
        let b = Bitmap(width: 8, height: 8, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for x in 0..<8 { b.setPixel(x: x, y: 4, to: RGBA(r: 0, g: 0, b: 0)) }   // horizontal wall
        FloodFill.fill(b, x: 0, y: 6, with: RGBA(r: 255, g: 0, b: 0))
        XCTAssertEqual(b.pixel(x: 7, y: 7), RGBA(r: 255, g: 0, b: 0), "filled above the wall")
        XCTAssertEqual(b.pixel(x: 7, y: 0).r, 255)
        XCTAssertEqual(b.pixel(x: 7, y: 0).g, 255, "below the wall untouched")
    }
}
