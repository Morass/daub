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

/// Fixes that came out of the 2026-09-17 review panel. Each test names the symptom the
/// user would have hit, because that is the part worth not regressing.
final class PanelFixTests: XCTestCase {
    private func white() -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }

    /// "Rotate Right" was turning the picture left: CoreGraphics rotates counter-clockwise
    /// for a positive angle in its y-up space, so the sign that reads correctly is wrong.
    func testRotateRightTurnsClockwise() {
        let b = Bitmap(width: 4, height: 2, fill: white())
        b.setPixel(x: 0, y: 1, to: RGBA(r: 255, g: 0, b: 0))      // visually top-left

        let right = b.rotatedQuarterTurn(clockwise: true, fill: white())
        XCTAssertEqual(right.width, 2)
        XCTAssertEqual(right.height, 4)
        // Clockwise sends the top-left corner to the top-right.
        XCTAssertEqual(right.pixel(x: right.width - 1, y: right.height - 1), RGBA(r: 255, g: 0, b: 0))

        let left = b.rotatedQuarterTurn(clockwise: false, fill: white())
        // Counter-clockwise sends it to the bottom-left.
        XCTAssertEqual(left.pixel(x: 0, y: 0), RGBA(r: 255, g: 0, b: 0))
    }

    func testFlipAndInvertAreTheirOwnInverse() {
        let b = Bitmap(width: 8, height: 8, fill: white())
        b.setPixel(x: 0, y: 7, to: RGBA(r: 12, g: 34, b: 56))
        b.flip(horizontally: true)
        XCTAssertEqual(b.pixel(x: 7, y: 7), RGBA(r: 12, g: 34, b: 56))
        b.flip(horizontally: true)
        XCTAssertEqual(b.pixel(x: 0, y: 7), RGBA(r: 12, g: 34, b: 56))

        b.invertColours()
        XCTAssertEqual(b.pixel(x: 0, y: 7), RGBA(r: 243, g: 221, b: 199))
        b.invertColours()
        XCTAssertEqual(b.pixel(x: 0, y: 7), RGBA(r: 12, g: 34, b: 56))
    }

    /// The screen redraw draws through `liveImage` instead of copying the canvas every
    /// frame. That is only correct if the image reports pixels written *after* it was made.
    func testLiveImageReadsThroughToLaterWrites() {
        let b = Bitmap(width: 4, height: 4, fill: white())
        let live = b.liveImage
        XCTAssertNotNil(live)
        b.setPixel(x: 1, y: 1, to: RGBA(r: 0, g: 0, b: 0))

        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(live!, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        let out = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // Row 2 from the top of the buffer is y = 1 in drawing coordinates.
        XCTAssertEqual(out[2 * 16 + 1 * 4], 0, "the write after liveImage() must be visible")
    }

    func testCroppedLiveImageMatchesTheCopyingCrop() {
        let b = Bitmap(width: 16, height: 16, fill: white())
        b.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        b.context.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
        let rect = CGRect(x: 8, y: 8, width: 8, height: 8)
        guard let live = b.croppedLiveImage(in: rect), let copied = b.croppedImage(in: rect) else {
            return XCTFail("both crops should succeed")
        }
        XCTAssertEqual(live.width, copied.width)
        XCTAssertEqual(live.height, copied.height)
    }

    /// Opening a malformed image must not trap the process on a 1.5 GB allocation.
    func testOversizeCanvasThrowsInsteadOfTrapping() {
        XCTAssertThrowsError(try Bitmap.checked(width: 100_000, height: 100_000))
        XCTAssertThrowsError(try Bitmap.checked(width: 0, height: 10))
        XCTAssertNoThrow(try Bitmap.checked(width: 4096, height: 4096))
    }

    /// Filling a region with the colour it already is used to cost an undo step.
    func testDiscardedCheckpointLeavesNoUndoStep() {
        let h = UndoHistory()
        let b = Bitmap(width: 4, height: 4, fill: white())
        h.record(b.makeImage())
        XCTAssertTrue(h.canUndo)
        XCTAssertNil(FloodFill.fill(b, x: 0, y: 0, with: RGBA(r: 255, g: 255, b: 255)))
        h.discardLastCheckpoint()
        XCTAssertFalse(h.canUndo, "a no-op fill must not leave a step to undo")
    }
}

/// Transparency: knocking a background out, erasing to nothing, and flattening for JPEG.
/// Replace-colour matches on colour and keeps coverage. Three separate rules, each of
/// which was wrong when the tool shipped: alpha counted as part of the colour, the whole
/// canvas was always searched, and every match was flattened to a hard edge.
final class ColourSwapTests: XCTestCase {
    private func white() -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }
    private let red = RGBA(r: 255, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 255)

    func testRegionLimitsTheSwapToTheSelection() {
        let b = Bitmap(width: 8, height: 8, fill: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let changed = b.replaceColour(matching: red, with: blue, tolerance: 0,
                                      in: CGRect(x: 2, y: 2, width: 3, height: 3))
        XCTAssertEqual(changed, 9)
        XCTAssertEqual(b.pixel(x: 3, y: 3), blue, "inside the region")
        XCTAssertEqual(b.pixel(x: 0, y: 0), red, "outside it, untouched")
    }

    func testEmptyCanvasIsNotNearAnyColour() {
        let b = Bitmap(width: 4, height: 4)                      // fully transparent
        b.setPixel(x: 1, y: 1, to: RGBA(r: 0, g: 0, b: 0))        // opaque black paint

        // A half-covered pixel is 50% away from empty in every premultiplied channel; with
        // alpha inside the tolerance this used to match, and clicking the empty area turned
        // every soft edge opaque.
        b.setPixel(x: 2, y: 2, to: RGBA(r: 128, g: 0, b: 0, a: 128))

        b.setPixel(x: 3, y: 3, to: RGBA(r: 2, g: 0, b: 0, a: 2))  // invisible rim of a stroke

        let changed = b.replaceColour(matching: RGBA(r: 0, g: 0, b: 0, a: 0),
                                      with: blue, tolerance: 128)
        XCTAssertEqual(changed, 14, "the 13 empty pixels and the invisible one")
        XCTAssertEqual(b.pixel(x: 3, y: 3), blue, "an alpha-2 rim counts as empty, not as art")
        XCTAssertEqual(b.pixel(x: 1, y: 1), RGBA(r: 0, g: 0, b: 0), "black paint survives")
        XCTAssertEqual(b.pixel(x: 2, y: 2).a, 128, "so does the soft edge")
        XCTAssertEqual(b.pixel(x: 0, y: 0), blue, "and the empty area takes the new colour whole")
    }

    func testSoftEdgesKeepTheirCoverage() {
        let b = Bitmap(width: 2, height: 2)
        b.setPixel(x: 0, y: 0, to: RGBA(r: 255, g: 0, b: 0))              // solid red
        b.setPixel(x: 1, y: 0, to: RGBA(r: 128, g: 0, b: 0, a: 128))      // half-covered red

        XCTAssertEqual(b.replaceColour(matching: red, with: blue, tolerance: 0), 2,
                       "the same red, at two different opacities")
        XCTAssertEqual(b.pixel(x: 0, y: 0), RGBA(r: 0, g: 0, b: 255))
        XCTAssertEqual(b.pixel(x: 1, y: 0).a, 128, "coverage preserved, not cut to a hard edge")
        XCTAssertEqual(b.pixel(x: 1, y: 0).b, 128, "and premultiplied to match")
    }

    func testKnockoutErasesInProportion() {
        let b = Bitmap(width: 2, height: 1)
        b.setPixel(x: 0, y: 0, to: RGBA(r: 255, g: 255, b: 255))
        b.setPixel(x: 1, y: 0, to: RGBA(r: 128, g: 128, b: 128, a: 128))  // soft white edge

        b.replaceColour(matching: RGBA(r: 255, g: 255, b: 255),
                        with: RGBA(r: 0, g: 0, b: 0, a: 0), tolerance: 0)
        XCTAssertEqual(b.pixel(x: 0, y: 0).a, 0)
        XCTAssertEqual(b.pixel(x: 1, y: 0).a, 0, "a half-covered white edge goes too")
    }

    /// The round trip through premultiplied bytes loses a count, so at tolerance 0 a soft
    /// edge must still match the colour it was painted with.
    func testASoftEdgeMatchesItsOwnColourAtZeroTolerance() {
        let straight = RGBA(r: 200, g: 50, b: 25)
        let b = Bitmap(width: 1, height: 1)
        b.setPixel(x: 0, y: 0, to: RGBA(r: 100, g: 25, b: 13, a: 128))   // the same colour, half covered

        XCTAssertEqual(b.replaceColour(matching: straight, with: blue, tolerance: 0), 1)
        XCTAssertEqual(b.pixel(x: 0, y: 0).a, 128, "still half covered")
    }

    func testSwappingAColourForItselfChangesNothing() {
        let b = Bitmap(width: 4, height: 4, fill: white())
        XCTAssertEqual(b.replaceColour(matching: RGBA(r: 255, g: 255, b: 255),
                                       with: RGBA(r: 255, g: 255, b: 255), tolerance: 0), 0,
                       "no pixels changed, so the caller can drop its undo checkpoint")
    }

    func testRegionOutsideTheCanvasIsANoOp() {
        let b = Bitmap(width: 4, height: 4, fill: white())
        XCTAssertEqual(b.replaceColour(matching: RGBA(r: 255, g: 255, b: 255), with: blue,
                                       tolerance: 0,
                                       in: CGRect(x: 40, y: 40, width: 4, height: 4)), 0)
        XCTAssertEqual(b.pixel(x: 0, y: 0), RGBA(r: 255, g: 255, b: 255))
    }
}

final class TransparencyTests: XCTestCase {
    private func white() -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }

    func testNewBitmapCanStartFullyTransparent() {
        let b = Bitmap(width: 4, height: 4)          // no fill
        XCTAssertTrue(b.hasTransparency())
        XCTAssertEqual(b.pixel(x: 0, y: 0).a, 0)
    }

    func testOpaqueCanvasReportsNoTransparency() {
        XCTAssertFalse(Bitmap(width: 4, height: 4, fill: white()).hasTransparency())
    }

    func testReplaceColourKnocksOutABackgroundWithinTolerance() {
        let b = Bitmap(width: 8, height: 8, fill: white())
        b.setPixel(x: 4, y: 4, to: RGBA(r: 250, g: 250, b: 250))    // near-white, e.g. JPEG noise
        b.setPixel(x: 5, y: 5, to: RGBA(r: 10, g: 20, b: 30))       // real subject

        let changed = b.replaceColour(matching: RGBA(r: 255, g: 255, b: 255),
                                      with: RGBA(r: 0, g: 0, b: 0, a: 0), tolerance: 12)
        XCTAssertEqual(changed, 63, "62 white pixels plus the near-white one")
        XCTAssertEqual(b.pixel(x: 0, y: 0).a, 0)
        XCTAssertEqual(b.pixel(x: 4, y: 4).a, 0, "tolerance caught the near-white pixel")
        XCTAssertEqual(b.pixel(x: 5, y: 5), RGBA(r: 10, g: 20, b: 30), "the subject survives")
        XCTAssertTrue(b.hasTransparency())
    }

    func testZeroToleranceLeavesNearMatchesAlone() {
        let b = Bitmap(width: 4, height: 4, fill: white())
        b.setPixel(x: 1, y: 1, to: RGBA(r: 250, g: 250, b: 250))
        b.replaceColour(matching: RGBA(r: 255, g: 255, b: 255),
                        with: RGBA(r: 0, g: 0, b: 0, a: 0), tolerance: 0)
        XCTAssertEqual(b.pixel(x: 1, y: 1).a, 255)
    }

    /// JPEG has no alpha: written straight out, a transparent canvas comes back black.
    func testFlatteningFillsHolesWithTheBackground() {
        let b = Bitmap(width: 4, height: 4)
        b.setPixel(x: 2, y: 2, to: RGBA(r: 200, g: 0, b: 0))
        guard let flat = b.flattened(onto: white()) else { return XCTFail("flatten failed") }

        let copy = Bitmap(width: 4, height: 4)
        copy.replace(with: flat)
        XCTAssertEqual(copy.pixel(x: 0, y: 0), RGBA(r: 255, g: 255, b: 255), "hole became white")
        XCTAssertEqual(copy.pixel(x: 2, y: 2).r, 200, "the painted pixel survived")
        XCTAssertFalse(copy.hasTransparency())
    }

    func testClearAllEmptiesTheCanvas() {
        let b = Bitmap(width: 4, height: 4, fill: white())
        b.clearAll()
        XCTAssertTrue(b.hasTransparency())
        XCTAssertEqual(b.pixel(x: 3, y: 3).a, 0)
    }
}
