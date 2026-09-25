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

/// Reported: a U-shaped region, filled with a colour within tolerance of the seed, is left
/// with gaps because the span scan skips a run after a visited pixel. Not reproduced — the
/// skipped run is the one the pushed seed claims — and this pins it.
final class FloodFillShapeTests: XCTestCase {
    func testAUShapeFillsCompletelyWhenTheNewColourIsWithinTolerance() {
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let b = Bitmap(width: 32, height: 32, fill: white)
        // A U: a wall down the middle from the top, leaving a channel round the bottom.
        b.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        b.context.fill(CGRect(x: 14, y: 8, width: 4, height: 24))

        let near = RGBA(r: 245, g: 245, b: 245)          // within tolerance of white
        let filled = FloodFill.fill(b, x: 0, y: 0, with: near, tolerance: 20)
        XCTAssertNotNil(filled)
        for y in 0..<32 {
            for x in 0..<32 where !(x >= 14 && x < 18 && y >= 8) {
                XCTAssertEqual(b.pixel(x: x, y: y), near,
                               "(\(x),\(y)) was left unfilled on the far side of the wall")
            }
        }
    }
}

final class UndoHistoryTests: XCTestCase {
    private func white() -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }

    private func canvas(_ value: UInt8) -> Bitmap {
        Bitmap(width: 2, height: 2,
               fill: CGColor(srgbRed: CGFloat(value) / 255, green: 0, blue: 0, alpha: 1))
    }

    private func step(_ value: UInt8) -> UndoStep { .whole(canvas(value).snapshot()) }

    /// The history does not touch pixels itself: the caller applies a step and hands back
    /// whatever reverses it. For these tests that is the step itself.
    private func passThrough(_ step: UndoStep) -> UndoStep? { step }

    func testUndoRedoRoundTrip() {
        let h = UndoHistory(limit: 4)
        XCTAssertFalse(h.canUndo)
        h.record(step(10))
        XCTAssertTrue(h.canUndo)
        XCTAssertTrue(h.undo(applying: passThrough))
        XCTAssertTrue(h.canRedo)
        XCTAssertTrue(h.redo(applying: passThrough))
        XCTAssertTrue(h.canUndo)
    }

    func testAStepThatCannotBeAppliedStaysPut() {
        let h = UndoHistory()
        h.record(step(1))
        XCTAssertFalse(h.undo(applying: { _ in nil }))
        XCTAssertTrue(h.canUndo, "a step that could not be applied must stay in the history")
        XCTAssertFalse(h.canRedo)
    }

    func testRecordingDropsTheRedoBranch() {
        let h = UndoHistory()
        h.record(step(1))
        _ = h.undo(applying: passThrough)
        XCTAssertTrue(h.canRedo)
        h.record(step(3))
        XCTAssertFalse(h.canRedo, "a new edit after undo abandons the redo branch")
    }

    func testHonoursItsLimit() {
        let h = UndoHistory(limit: 3)
        for i in 0..<10 { h.record(step(UInt8(i))) }
        XCTAssertEqual(h.depth, 3)
    }

    /// The point of the patches: a stroke on a big canvas costs the tiles it crossed, and
    /// the history has no baseline canvas at all. Whole snapshots would be 3 GB here.
    func testAHistoryOfStrokesCostsNoCanvasAtAll() {
        let b = Bitmap(width: 2048, height: 2048, fill: white())    // 16 MB of canvas
        let h = UndoHistory()
        for step in 0..<32 {
            let patch = PixelPatch(canvas: b)
            h.record(.patch(patch))
            let dab = CGRect(x: CGFloat(step) * 3, y: 0, width: 2, height: 2)
            patch.capture(b, rect: dab)
            b.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            b.context.fill(dab)
        }
        XCTAssertEqual(h.depth, 32)
        XCTAssertLessThan(h.byteCount, 2048 * 2048 * 4 / 4,
                          "32 dabs must cost a fraction of one canvas, not 32 of them")
    }

    /// Whole-canvas steps — a resize, a rotate — really do cost a canvas each, which is what
    /// the byte budget is for.
    func testTheByteBudgetDropsTheOldestSteps() {
        let b = Bitmap(width: 256, height: 256, fill: white())
        let canvasBytes = 256 * 256 * 4
        let h = UndoHistory(limit: 32, byteBudget: 4 * canvasBytes)
        for value in 0..<10 {
            b.invertColours()
            b.setPixel(x: 0, y: 0, to: RGBA(r: UInt8(value), g: 0, b: 0))
            h.record(.whole(b.snapshot(reusing: h.newestPastSnapshot)))
        }
        XCTAssertLessThan(h.depth, 10, "the budget must have dropped the oldest steps")
        XCTAssertLessThanOrEqual(h.byteCount, 4 * canvasBytes)
        XCTAssertTrue(h.canUndo, "the budget must never take the last step away")
    }

    func testOneStepSurvivesEvenWhenItIsOverBudget() {
        let h = UndoHistory(byteBudget: 1 << 20)   // clamped to 1 MB; the snapshot is 4 MB
        let big = Bitmap(width: 1024, height: 1024, fill: white())
        h.record(.whole(big.snapshot()))
        XCTAssertTrue(h.canUndo)
        XCTAssertEqual(h.depth, 1)
    }

    /// A click that changes nothing must not cost the user the history they had.
    func testACancelledCheckpointPutsBackWhatRecordingItCost() {
        let big = Bitmap(width: 512, height: 512, fill: white())
        let h = UndoHistory(byteBudget: 1 << 20)      // one 1 MB canvas fills it exactly
        h.record(.whole(big.snapshot()))
        big.invertColours()
        let before = h.depth
        h.record(.whole(big.snapshot()))              // the no-op's checkpoint
        h.discardLastCheckpoint()
        XCTAssertEqual(h.depth, before, "cancelling must not cost a step that was already there")
        XCTAssertTrue(h.canUndo)
    }

    func testACancelledCheckpointPutsBackTheRedoBranch() {
        let h = UndoHistory()
        h.record(step(1))
        _ = h.undo(applying: passThrough)
        XCTAssertTrue(h.canRedo)
        h.record(step(3))            // a click that turns out to change nothing
        h.discardLastCheckpoint()
        XCTAssertTrue(h.canRedo, "a cancelled checkpoint must not throw away the redo branch")
    }

    /// Undo pushes what it replaced onto the redo stack; on a canvas bigger than the budget
    /// that push used to be trimmed away immediately, so ⇧⌘Z could not undo the ⌘Z.
    func testUndoKeepsTheRedoItJustCreated() {
        let big = Bitmap(width: 1024, height: 512, fill: white())   // 2 MB, over the budget
        let h = UndoHistory(byteBudget: 1 << 20)
        h.record(.whole(big.snapshot()))
        big.invertColours()
        XCTAssertTrue(h.undo(applying: passThrough))
        XCTAssertTrue(h.canRedo, "the step just undone must still be redoable")
    }

    /// A patch is empty when it is recorded and fills as the tool draws, so the budget
    /// check at record time sees none of its weight. The step ends; the budget must bite.
    func testTheBudgetIsEnforcedOnceAStepHasFinishedGrowing() {
        let b = Bitmap(width: 512, height: 512, fill: white())     // 1 MB
        let h = UndoHistory(byteBudget: 1 << 20)
        for _ in 0..<3 {
            let patch = PixelPatch(canvas: b)
            h.record(.patch(patch))
            patch.captureAll(b)                                    // the whole canvas
            b.invertColours()
        }
        XCTAssertGreaterThan(h.byteCount, h.byteBudget, "nothing has trimmed yet")
        h.enforceBudget()
        XCTAssertLessThanOrEqual(h.byteCount, h.byteBudget, "finishing a step brings it back")
        XCTAssertTrue(h.canUndo)
    }

    /// Promoting a step to a whole-canvas one can push the history over budget. What that
    /// evicts belongs to the same rollback as the step itself.
    func testCancellingAPromotedStepPutsBackWhatPromotingItCost() {
        let b = Bitmap(width: 512, height: 512, fill: white())     // 1 MB
        let h = UndoHistory(byteBudget: 1 << 20)
        let first = PixelPatch(canvas: b)
        h.record(.patch(first))
        first.capture(b, rect: CGRect(x: 0, y: 0, width: 4, height: 4))
        b.setPixel(x: 1, y: 1, to: RGBA(r: 0, g: 0, b: 0))
        let before = h.depth
        h.record(.patch(PixelPatch(canvas: b)))                    // the paste's checkpoint
        h.replaceNewestStep(with: .whole(b.snapshot()))            // …which grows the canvas
        h.discardLastCheckpoint()
        XCTAssertEqual(h.depth, before, "cancelling a promoted step must restore the history")
        XCTAssertTrue(h.canUndo)
    }

    /// Keeping a cancelled step's rollback must not cost the user live undo steps, and the
    /// memory it does hold must be released at the next edit rather than accumulating.
    func testTheRollbackIsTransientAndDoesNotEvictLiveSteps() {
        let b = Bitmap(width: 512, height: 512, fill: white())     // 1 MB a snapshot
        let h = UndoHistory(byteBudget: 3 << 20)
        var depths: [Int] = []
        for value in 0..<8 {
            b.setPixel(x: value, y: 0, to: RGBA(r: UInt8(value), g: 0, b: 0))
            h.record(.whole(b.snapshot()))
            depths.append(h.depth)
            XCTAssertLessThanOrEqual(h.byteCount, h.byteBudget, "the reachable history is bounded")
            // The overshoot is one recording's worth, never a growing one.
            XCTAssertLessThanOrEqual(h.retainedByteCount, h.byteBudget + (1 << 20) * 2)
        }
        XCTAssertEqual(depths.last, depths[3], "the depth settles instead of shrinking away")
        XCTAssertTrue(h.canUndo)
    }

    /// Escape on a paste is not an undo: it puts the pixels back and the step never happened,
    /// so whatever was redoable before is redoable still.
    func testCancellingAStepKeepsTheRedoBranchThatWasAlreadyThere() {
        let h = UndoHistory()
        h.record(step(1))
        _ = h.undo(applying: passThrough)
        XCTAssertTrue(h.canRedo, "there is a redo branch to protect")
        h.record(step(2))                       // the paste's checkpoint
        var applied = false
        XCTAssertTrue(h.cancelLastCheckpoint(applying: { _ in applied = true; return true }))
        XCTAssertTrue(applied, "cancelling has to put the pixels back")
        XCTAssertTrue(h.canRedo, "and must not leave the redo branch destroyed")
        XCTAssertFalse(h.canUndo, "the cancelled step is gone, not undone")
    }

    /// A step that changes the canvas size is stored whole; the newest such snapshot is
    /// what a new one shares its unchanged tiles with.
    func testWholeStepsStillShareTheirTiles() {
        let b = Bitmap(width: 512, height: 512, fill: white())
        let h = UndoHistory()
        h.record(.whole(b.snapshot()))
        b.setPixel(x: 5, y: 5, to: RGBA(r: 0, g: 0, b: 0))
        let second = b.snapshot(reusing: h.newestPastSnapshot)
        h.record(.whole(second))
        XCTAssertLessThan(h.byteCount, 512 * 512 * 4 * 2 - 1,
                          "the second snapshot must share the tiles the edit did not touch")
    }
}

/// A patch remembers only what a step touched. This is what keeps a history of strokes from
/// costing a canvas apiece.
final class PixelPatchTests: XCTestCase {
    private func white() -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }
    private let black = RGBA(r: 0, g: 0, b: 0)

    func testAPatchCostsTheTilesItTouchedAndNoMore() {
        let b = Bitmap(width: 2048, height: 2048, fill: white())      // 16 MB of canvas
        let patch = PixelPatch(canvas: b)
        patch.capture(b, rect: CGRect(x: 10, y: 10, width: 4, height: 4))
        b.setPixel(x: 11, y: 11, to: black)
        XCTAssertEqual(patch.tileCount, 1)
        XCTAssertEqual(patch.byteCount, Bitmap.snapshotTileSize * Bitmap.snapshotTileSize * 4)
        XCTAssertLessThan(patch.byteCount, 2048 * 2048 * 4 / 100, "a dot must not cost a canvas")
    }

    func testApplyingAPatchUndoesAndThenRedoes() {
        let b = Bitmap(width: 300, height: 200, fill: white())
        let patch = PixelPatch(canvas: b)
        let spot = CGRect(x: 40, y: 30, width: 6, height: 6)
        patch.capture(b, rect: spot)
        b.context.setFillColor(black.cgColor)
        b.context.fill(spot)
        XCTAssertEqual(b.pixel(x: 42, y: 32), black)

        XCTAssertTrue(patch.apply(to: b))
        XCTAssertEqual(b.pixel(x: 42, y: 32), RGBA(r: 255, g: 255, b: 255), "undone")
        XCTAssertTrue(patch.apply(to: b))
        XCTAssertEqual(b.pixel(x: 42, y: 32), black, "and redone by the very same patch")
    }

    /// Tools work with the origin at the bottom left; memory runs top-down. A patch that
    /// got that backwards would restore the mirror image of the right region.
    func testCaptureUsesDrawingCoordinates() {
        let b = Bitmap(width: 256, height: 256, fill: white())
        let patch = PixelPatch(canvas: b)
        let low = CGRect(x: 0, y: 0, width: 8, height: 8)      // bottom-left in drawing space
        patch.capture(b, rect: low)
        b.setPixel(x: 2, y: 2, to: black)                       // inside it
        b.setPixel(x: 2, y: 253, to: black)                     // the mirrored position
        patch.apply(to: b)
        XCTAssertEqual(b.pixel(x: 2, y: 2), RGBA(r: 255, g: 255, b: 255), "the captured corner came back")
        XCTAssertEqual(b.pixel(x: 2, y: 253), black, "the other corner was never captured")
    }

    func testCapturingTheSameTileTwiceKeepsTheOldestPixels() {
        let b = Bitmap(width: 128, height: 128, fill: white())
        let patch = PixelPatch(canvas: b)
        let spot = CGRect(x: 1, y: 1, width: 2, height: 2)
        patch.capture(b, rect: spot)            // white
        b.setPixel(x: 1, y: 1, to: black)
        patch.capture(b, rect: spot)            // must not overwrite the white it holds
        patch.apply(to: b)
        XCTAssertEqual(b.pixel(x: 1, y: 1), RGBA(r: 255, g: 255, b: 255),
                       "a second touch in one step must not re-record the pixels")
    }

    func testAPatchIgnoresACanvasThatChangedSize() {
        let b = Bitmap(width: 64, height: 64, fill: white())
        let patch = PixelPatch(canvas: b)
        patch.capture(b, rect: b.bounds)
        let resized = Bitmap(width: 128, height: 64, fill: white())
        XCTAssertFalse(patch.apply(to: resized), "a patch is only valid for its own geometry")
    }

    /// One black pixel on a white canvas used to cost the whole canvas: the colour swap
    /// declared its whole search area up front. It now journals the rows that move.
    func testAColourSwapCostsTheRowsItChanges() {
        let b = Bitmap(width: 1024, height: 1024, fill: white())     // 4 MB
        b.setPixel(x: 500, y: 500, to: black)
        let patch = PixelPatch(canvas: b)
        let changed = b.replaceColour(matching: black, with: RGBA(r: 255, g: 0, b: 0),
                                      tolerance: 0, in: nil,
                                      willTouch: { patch.capture(b, rect: $0) })
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(patch.tileCount, 1, "one pixel, one tile")
        XCTAssertEqual(b.pixel(x: 500, y: 500), RGBA(r: 255, g: 0, b: 0))
        patch.apply(to: b)
        XCTAssertEqual(b.pixel(x: 500, y: 500), black, "and it undoes exactly")
    }

    func testCaptureClipsToTheCanvas() {
        let b = Bitmap(width: 40, height: 40, fill: white())
        let patch = PixelPatch(canvas: b)
        patch.capture(b, rect: CGRect(x: -500, y: -500, width: 5000, height: 5000))
        XCTAssertEqual(patch.tileCount, 1)
        patch.capture(b, rect: CGRect(x: 100, y: 100, width: 10, height: 10))
        XCTAssertEqual(patch.tileCount, 1, "a rectangle entirely off the canvas captures nothing")
    }
}

/// The tiles themselves: a snapshot must come back byte for byte, share what did not
/// change, and survive a canvas that is not a whole number of tiles wide.
final class CanvasSnapshotTests: XCTestCase {
    private func white() -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }

    func testRestoreIsExact() {
        let b = Bitmap(width: 300, height: 173, fill: white())   // deliberately ragged
        b.setPixel(x: 299, y: 172, to: RGBA(r: 1, g: 2, b: 3))
        b.setPixel(x: 130, y: 44, to: RGBA(r: 9, g: 8, b: 7))
        let snap = b.snapshot()
        b.invertColours()
        b.setPixel(x: 0, y: 0, to: RGBA(r: 200, g: 100, b: 50))
        XCTAssertTrue(b.restore(snap))
        XCTAssertEqual(b.pixel(x: 299, y: 172), RGBA(r: 1, g: 2, b: 3), "the last tile is ragged")
        XCTAssertEqual(b.pixel(x: 130, y: 44), RGBA(r: 9, g: 8, b: 7))
        XCTAssertEqual(b.pixel(x: 0, y: 0), RGBA(r: 255, g: 255, b: 255))
    }

    func testUnchangedTilesAreTheSameObjects() {
        let b = Bitmap(width: 512, height: 512, fill: white())
        let first = b.snapshot()
        b.setPixel(x: 5, y: 5, to: RGBA(r: 0, g: 0, b: 0))
        let second = b.snapshot(reusing: first)
        let across = 512 / Bitmap.snapshotTileSize
        XCTAssertEqual(first.tileCount, across * across)
        XCTAssertEqual(second.sharedTileCount(with: first), across * across - 1,
                       "only the touched tile is new")
    }

    func testASnapshotOfAnotherSizeSharesNothing() {
        let small = Bitmap(width: 64, height: 64, fill: white())
        let large = Bitmap(width: 256, height: 256, fill: white())
        let taken = large.snapshot(reusing: small.snapshot())
        XCTAssertEqual(taken.width, 256)
        XCTAssertFalse(small.restore(taken), "a snapshot of another size must be refused")
    }

    /// `(width + tileSize - 1)` overflows for a tileSize of Int.max. The parameter is
    /// public, so it has to survive one.
    func testAnAbsurdTileSizeIsClampedToTheCanvas() {
        let b = Bitmap(width: 200, height: 40, fill: white())
        b.setPixel(x: 199, y: 39, to: RGBA(r: 7, g: 7, b: 7))
        let snap = b.snapshot(tileSize: Int.max)
        XCTAssertEqual(snap.tileCount, 1)
        b.clearAll()
        XCTAssertTrue(b.restore(snap))
        XCTAssertEqual(b.pixel(x: 199, y: 39), RGBA(r: 7, g: 7, b: 7))
    }

    /// `Bitmap.init` clamps each side to 32768 and never looks at the area, so the New and
    /// Resize sheets could ask it for a 4 GB canvas.
    func testTheAreaLimitCatchesWhatTheSideLimitsDoNot() {
        XCTAssertTrue(Bitmap.isAllocatable(width: 8192, height: 8192))
        XCTAssertFalse(Bitmap.isAllocatable(width: 32768, height: 32768),
                       "inside both side limits, but 4 GB of pixels")
        XCTAssertFalse(Bitmap.isAllocatable(width: 0, height: 10))
        XCTAssertFalse(Bitmap.isAllocatable(width: Int.max, height: Int.max))
    }

    /// A crop or a resize throws the old `Bitmap` away. A frame CoreGraphics is still
    /// holding must not be left pointing at freed pixels.
    func testALiveImageKeepsItsBitmapAlive() {
        weak var weakBitmap: Bitmap?
        var image: CGImage?
        do {
            let b = Bitmap(width: 8, height: 8, fill: white())
            weakBitmap = b
            image = b.liveImage
        }
        XCTAssertNotNil(image)
        XCTAssertNotNil(weakBitmap, "the live image must keep the buffer it reads from alive")
        image = nil
        XCTAssertNil(weakBitmap, "and let it go when the image does")
    }

    func testSnapshotSurvivesACanvasSmallerThanOneTile() {
        let b = Bitmap(width: 3, height: 2, fill: white())
        b.setPixel(x: 2, y: 1, to: RGBA(r: 4, g: 5, b: 6))
        let snap = b.snapshot()
        XCTAssertEqual(snap.tileCount, 1)
        XCTAssertEqual(snap.byteCount, 3 * 2 * 4)
        b.clearAll()
        b.restore(snap)
        XCTAssertEqual(b.pixel(x: 2, y: 1), RGBA(r: 4, g: 5, b: 6))
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

    /// Regression: the canvas redrew as it had been *before* a whole-canvas operation.
    ///
    /// `liveImage` used to hand back one cached CGImage for the life of the buffer.
    /// CoreGraphics treats a data provider over raw memory as immutable and caches the
    /// raster it uploads for an image, keyed on the image — so the on-screen full-canvas
    /// redraw kept painting the first raster it ever saw. Applying a gradient and then
    /// drawing showed the gradient only inside the dirty rectangles the stroke repainted,
    /// in blocks tracing the stroke, with stale pixels everywhere else. A distinct image
    /// per call is the fix, so pin that rather than the symptom.
    func testLiveImageIsNotCachedBetweenCalls() {
        let b = Bitmap(width: 4, height: 4, fill: white())
        guard let first = b.liveImage, let second = b.liveImage else {
            return XCTFail("liveImage failed")
        }
        XCTAssertFalse(first === second, "liveImage must mint a new CGImage each call")

        b.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        b.context.fill(b.bounds)
        guard let third = b.liveImage else { return XCTFail("liveImage failed") }
        XCTAssertFalse(third === first, "a whole-canvas fill must not hand back the old image")
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
        h.record(.patch(PixelPatch(canvas: b)))
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

/// Pasting a screenshot onto a smaller canvas: the rules for how far the canvas grows.
final class CanvasFitTests: XCTestCase {
    func testCanvasGrowsToHoldALargerImage() {
        let grown = CanvasFit.grown(canvas: CGSize(width: 1024, height: 768),
                                    toFit: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(grown, CGSize(width: 2880, height: 1800))
    }

    func testCanvasNeverShrinks() {
        let canvas = CGSize(width: 1024, height: 768)
        XCTAssertEqual(CanvasFit.grown(canvas: canvas, toFit: CGSize(width: 64, height: 64)), canvas,
                       "a small paste leaves the picture the size it was")
    }

    func testGrowthIsPerAxis() {
        // A wide, short image must not lop the bottom off a tall canvas.
        let grown = CanvasFit.grown(canvas: CGSize(width: 400, height: 2000),
                                    toFit: CGSize(width: 3000, height: 100))
        XCTAssertEqual(grown, CGSize(width: 3000, height: 2000))
    }

    func testExactFitDoesNotResize() {
        let canvas = CGSize(width: 800, height: 600)
        XCTAssertEqual(CanvasFit.grown(canvas: canvas, toFit: canvas), canvas)
        XCTAssertTrue(CanvasFit.fits(canvas, in: canvas))
        XCTAssertFalse(CanvasFit.fits(CGSize(width: 801, height: 600), in: canvas))
    }

    /// An image past the pixel budget must not produce a canvas Daub cannot allocate, and
    /// must not shrink the picture already open either.
    func testOverLargeImageLeavesTheCanvasAlone() {
        let canvas = CGSize(width: 1024, height: 768)
        let huge = CGSize(width: 40_000, height: 40_000)
        let grown = CanvasFit.grown(canvas: canvas, toFit: huge)
        XCTAssertEqual(grown, canvas)
    }

    func testGrowthStaysInsideWhatBitmapWillAllocate() {
        // Just inside the pixel budget: this one is allowed to grow.
        let ok = CanvasFit.grown(canvas: CGSize(width: 100, height: 100),
                                 toFit: CGSize(width: 8192, height: 8000))
        XCTAssertEqual(ok, CGSize(width: 8192, height: 8000))
        XCTAssertLessThanOrEqual(Int(ok.width) * Int(ok.height), Bitmap.maxPixels)

        // Past it: the canvas is left alone rather than grown to something unallocatable.
        let canvas = CGSize(width: 1024, height: 768)
        XCTAssertEqual(CanvasFit.grown(canvas: canvas, toFit: CGSize(width: 9000, height: 9000)),
                       canvas)
    }

    /// Fractional or sub-pixel sizes must never come back as a request to shrink: the
    /// caller resizes the canvas to whatever this returns.
    func testFractionalSizesNeverShrinkTheCanvas() {
        let tiny = CanvasFit.grown(canvas: CGSize(width: 0.1, height: 0.1),
                                   toFit: CGSize(width: 0.1, height: 0.1))
        XCTAssertGreaterThanOrEqual(tiny.width, 1)
        XCTAssertGreaterThanOrEqual(tiny.height, 1)

        let canvas = CGSize(width: 10.6, height: 10.6)
        let grown = CanvasFit.grown(canvas: canvas, toFit: CGSize(width: 1, height: 1))
        XCTAssertGreaterThanOrEqual(grown.width, 10, "rounding must not lose a column")
        XCTAssertGreaterThanOrEqual(grown.height, 10)
    }

    /// A CGFloat that cannot become an Int must not trap the conversion.
    func testNonsenseSizesDoNotTrap() {
        let canvas = CGSize(width: 640, height: 480)
        XCTAssertEqual(CanvasFit.grown(canvas: canvas, toFit: CGSize(width: CGFloat.infinity, height: CGFloat.nan)),
                       canvas)
        XCTAssertEqual(CanvasFit.grown(canvas: canvas, toFit: CGSize(width: 1e30, height: 1e30)),
                       canvas)
    }

    func testDegenerateSizesAreSurvivable() {
        let grown = CanvasFit.grown(canvas: CGSize(width: 0, height: 0),
                                    toFit: CGSize(width: 10, height: 10))
        XCTAssertEqual(grown, CGSize(width: 10, height: 10))
    }
}

final class BrushCursorTests: XCTestCase {
    /// The outline is the stroke's real width on screen: size times zoom.
    func testOutlineFollowsSizeAndZoom() {
        XCTAssertEqual(BrushCursor.viewDiameter(tip: .circle, size: 12, zoom: 1), 12)
        XCTAssertEqual(BrushCursor.viewDiameter(tip: .circle, size: 12, zoom: 4), 48)
        XCTAssertEqual(BrushCursor.viewDiameter(tip: .circle, size: 12, zoom: 0.5), 6)
    }

    /// The airbrush knob is a radius; its outline must span the whole spray area.
    func testSprayOutlineIsTheWholeArea() {
        XCTAssertEqual(BrushCursor.viewDiameter(tip: .spray, size: 14, zoom: 1), 29)
    }

    /// The pencil and eraser stamp whole pixels, so a fractional size draws its floor.
    func testSquareTipIsWholePixels() {
        XCTAssertEqual(BrushCursor.canvasDiameter(tip: .square, size: 12.7), 12)
        XCTAssertEqual(BrushCursor.canvasDiameter(tip: .square, size: 0.2), 1)
    }

    /// Too small to read or too big to draw: the caller falls back to a crosshair
    /// instead of showing an outline that lies about the width.
    func testUnreadableOrUndrawableSizesFallBack() {
        XCTAssertNil(BrushCursor.viewDiameter(tip: .square, size: 1, zoom: 1))
        XCTAssertNil(BrushCursor.viewDiameter(tip: .circle, size: 48, zoom: 8))
        XCTAssertNil(BrushCursor.viewDiameter(tip: .circle, size: 12, zoom: .nan))
        XCTAssertNotNil(BrushCursor.viewDiameter(tip: .square, size: 1, zoom: 8))
    }
}
