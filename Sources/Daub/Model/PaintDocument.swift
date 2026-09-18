import AppKit
import DaubCore

/// The pixels, their history, and where they came from.
///
/// Deliberately *not* an ObservableObject: a stroke mutates this hundreds of times per
/// second and SwiftUI must not hear about any of it. The canvas view redraws itself; the
/// UI is refreshed only at commit boundaries, by `Editor`.
final class PaintDocument {
    private(set) var bitmap: Bitmap
    let history = UndoHistory(limit: 32)
    var fileURL: URL?
    var isDirty = false

    var width: Int { bitmap.width }
    var height: Int { bitmap.height }
    var size: CGSize { CGSize(width: bitmap.width, height: bitmap.height) }
    var bounds: CGRect { bitmap.bounds }
    var context: CGContext { bitmap.context }

    var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }

    /// True when the canvas is allowed to hold transparency. It drives three things: the
    /// checkerboard behind the picture, whether the eraser rubs through to nothing, and
    /// what colour a canvas resize pads with.
    private(set) var hasAlpha = false

    init(width: Int = 1024, height: Int = 768, transparent: Bool = false) {
        bitmap = Bitmap(width: width, height: height,
                        fill: transparent ? nil : NSColor.white.cgColor)
        hasAlpha = transparent
    }

    /// Draw onto a *clear* bitmap, not a white one. Filling white first and compositing
    /// over it destroyed the transparency of every PNG and window screenshot on the way in
    /// — and then asked the flattened result whether it had any, which it never did. A
    /// picture with no alpha comes out opaque either way.
    init(image: CGImage, url: URL?) throws {
        bitmap = try Bitmap.checked(width: image.width, height: image.height)
        bitmap.context.draw(image, in: bitmap.bounds)
        fileURL = url
        hasAlpha = bitmap.hasTransparency()
    }

    /// Mark the pixels changed without opening an undo step. Painting inside one drag
    /// checkpoints once at mouse-down, so a save that lands mid-drag would otherwise
    /// clear the dirty flag while the airbrush is still spraying.
    func markDirty() { isDirty = true }

    // MARK: - History

    /// Open an undo step. Call once immediately before a mutation that should be undoable
    /// as a single step — and then tell it, through `willTouch`, every rectangle the step
    /// is about to draw into, *before* it draws there.
    func checkpoint() {
        let patch = PixelPatch(canvas: bitmap)
        history.record(.patch(patch))
        openPatch = patch
        if PaintDocument.verifiesUndo { verificationStack.append(bitmap.snapshot()) }
        wasDirtyBeforeCheckpoint = isDirty
        isDirty = true
    }

    /// Open an undo step for an operation that changes the *size* of the canvas — a resize,
    /// a crop, a rotate. There is no "the pixels under this rectangle" across a change like
    /// that, so this one costs the old canvas.
    func checkpointWholeCanvas() {
        history.record(.whole(bitmap.snapshot(reusing: history.newestPastSnapshot)))
        openPatch = nil
        if PaintDocument.verifiesUndo { verificationStack.append(bitmap.snapshot()) }
        wasDirtyBeforeCheckpoint = isDirty
        isDirty = true
    }

    /// The step in progress turns out to change the canvas size after all (a paste that
    /// grows the picture): swap its patch for a whole-canvas snapshot, taken now, before
    /// the resize.
    func promoteCheckpointToWholeCanvas() {
        guard let patch = openPatch, patch.isEmpty else { return }
        history.replaceNewestStep(with: .whole(bitmap.snapshot(reusing: history.newestPastSnapshot)))
        openPatch = nil
    }

    /// Everything a step is about to change, in drawing coordinates, before it changes.
    /// Round outwards: a rectangle that is too big costs a tile, one that is too small
    /// costs correctness.
    func willTouch(_ rect: CGRect) { openPatch?.capture(bitmap, rect: rect) }

    /// For the operations that really do touch every pixel: invert, clear, a colour swap
    /// across the whole picture.
    func willTouchEverything() { openPatch?.captureAll(bitmap) }

    /// The area a *line* covers, which is not its bounding box: a hairline from one corner
    /// of a 24-megapixel picture to the other has a bounding box of the whole picture and
    /// covers a thousandth of it. Walk it instead.
    func willTouchAlong(from a: CGPoint, to b: CGPoint, reach: CGFloat) {
        guard openPatch != nil else { return }
        let span = max(1, reach)
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / span))
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            willTouch(CGRect(x: p.x - span, y: p.y - span, width: span * 2, height: span * 2))
        }
    }

    /// The four edges of a rectangle, for an outline that is not filled — the same argument
    /// as `willTouchAlong`, in two dimensions.
    func willTouchOutline(of rect: CGRect, reach: CGFloat) {
        let r = rect.insetBy(dx: -reach, dy: -reach)
        let band = max(1, reach * 2) + min(r.width, r.height) * 0
        let thickness = min(band, min(r.width, r.height))
        willTouch(CGRect(x: r.minX, y: r.minY, width: r.width, height: thickness))
        willTouch(CGRect(x: r.minX, y: r.maxY - thickness, width: r.width, height: thickness))
        willTouch(CGRect(x: r.minX, y: r.minY, width: thickness, height: r.height))
        willTouch(CGRect(x: r.maxX - thickness, y: r.minY, width: thickness, height: r.height))
    }

    /// The step being journalled, if any.
    private(set) var openPatch: PixelPatch?

    /// Self-test only: keep a full snapshot beside every step and check, on undo, that the
    /// patch put the canvas back exactly. A tool that forgets to declare a rectangle it
    /// draws into is otherwise a silent wrong-pixels bug, and this is what catches it.
    static var verifiesUndo = false
    private static var verificationFailures: [String] = []

    /// Read the failures since the last read and clear them.
    static func takeVerificationFailures() -> [String] {
        defer { verificationFailures.removeAll() }
        return verificationFailures
    }
    private var verificationStack: [CanvasSnapshot] = []

    /// What `isDirty` was before the checkpoint, so cancelling one can put it back: an
    /// action that turned out to change nothing must not leave a saved file looking edited.
    private var wasDirtyBeforeCheckpoint = false

    @discardableResult
    func undo() -> Bool {
        openPatch = nil
        let undone = history.undo(applying: { apply($0) })
        if undone, PaintDocument.verifiesUndo, let expected = verificationStack.popLast(),
           !bitmap.snapshot().hasSamePixels(as: expected) {
            PaintDocument.verificationFailures.append(
                "undo did not put every pixel back — a tool drew somewhere it did not declare")
        }
        return undone
    }

    @discardableResult
    func redo() -> Bool {
        openPatch = nil
        return history.redo(applying: { apply($0) })
    }

    /// Put a step's pixels on the canvas and hand back the step that reverses it.
    private func apply(_ step: UndoStep) -> UndoStep? {
        switch step {
        case .patch(let patch):
            guard patch.apply(to: bitmap) else { return nil }
            isDirty = true
            return .patch(patch)                  // a patch is its own inverse
        case .whole(let snapshot):
            let current = bitmap.snapshot()
            adopt(snapshot)
            return .whole(current)
        }
    }

    /// Restoring a snapshot may also restore a different canvas size (undoing a resize), in
    /// which case the bitmap is rebuilt at that size first — the snapshot then overwrites
    /// every pixel of it, so what it is filled with does not matter.
    private func adopt(_ snapshot: CanvasSnapshot) {
        if snapshot.width != bitmap.width || snapshot.height != bitmap.height {
            bitmap = Bitmap(width: snapshot.width, height: snapshot.height)
        }
        bitmap.restore(snapshot)
        isDirty = true
    }

    // MARK: - Whole-canvas operations

    func resizeCanvas(to newWidth: Int, _ newHeight: Int, fill: NSColor) {
        checkpointWholeCanvas()
        bitmap = bitmap.resized(to: newWidth, newHeight,
                                fill: hasAlpha ? NSColor.clear.cgColor : fill.cgColor)
    }

    /// Grow the canvas so a pasted image fits, keeping the picture in its top-left corner
    /// and padding the new area with `fill`.
    ///
    /// It takes no checkpoint of its own: the paste that calls it has already taken one, so
    /// the grow and the paste undo together as a single ⌘Z.
    func growCanvas(to size: CGSize, fill: NSColor) {
        let newWidth = max(width, Int(size.width.rounded()))
        let newHeight = max(height, Int(size.height.rounded()))
        guard newWidth != width || newHeight != height else { return }
        bitmap = bitmap.resized(to: newWidth, newHeight,
                                fill: hasAlpha ? NSColor.clear.cgColor : fill.cgColor)
        isDirty = true
    }

    func scaleImage(to newWidth: Int, _ newHeight: Int) {
        checkpointWholeCanvas()
        guard let image = bitmap.makeImage() else { return }
        let out = Bitmap(width: newWidth, height: newHeight,
                         fill: hasAlpha ? nil : NSColor.white.cgColor)
        out.context.interpolationQuality = .high
        out.context.draw(image, in: out.bounds)
        bitmap = out
    }

    func clear(with color: NSColor) {
        checkpoint()
        willTouchEverything()
        if hasAlpha {
            bitmap.clearAll()
        } else {
            bitmap.context.setFillColor(color.cgColor)
            bitmap.context.fill(bitmap.bounds)
        }
    }

    /// Knock a colour out of the picture — the "my PNG has a white background and I want
    /// it transparent" operation, which is the only reason most people ever want alpha.
    @discardableResult
    func makeColourTransparent(_ colour: NSColor, tolerance: Int, in region: CGRect? = nil) -> Int {
        guard let target = RGBA(colour.cgColor) else { return 0 }
        checkpoint()
        let changed = bitmap.replaceColour(matching: target,
                                           with: RGBA(r: 0, g: 0, b: 0, a: 0),
                                           tolerance: tolerance, in: region,
                                           willTouch: { [weak self] span in self?.willTouch(span) })
        if changed > 0 { hasAlpha = true } else { cancelCheckpoint() }
        return changed
    }

    /// - Parameter region: the selection, when there is one; `nil` swaps across the whole
    ///   picture. Either way a run that matched nothing costs no undo step.
    @discardableResult
    func replaceColour(_ colour: NSColor, with replacement: NSColor, tolerance: Int,
                       in region: CGRect? = nil) -> Int {
        guard let target = RGBA(colour.cgColor), let new = RGBA(replacement.cgColor) else { return 0 }
        checkpoint()
        let changed = bitmap.replaceColour(matching: target, with: new,
                                           tolerance: tolerance, in: region,
                                           willTouch: { [weak self] span in self?.willTouch(span) })
        if changed == 0 { cancelCheckpoint() }
        return changed
    }

    /// Throw away everything outside `rect`. Cheap, and the operation a screenshot needs
    /// most often.
    func crop(to rect: CGRect) {
        let r = rect.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1, let cut = bitmap.croppedImage(in: r) else { return }
        checkpointWholeCanvas()
        let out = Bitmap(width: Int(r.width), height: Int(r.height),
                         fill: hasAlpha ? nil : NSColor.white.cgColor)
        out.context.draw(cut, in: out.bounds)
        bitmap = out
    }

    /// The eraser rubs through to nothing on a canvas that holds alpha, and paints the
    /// background colour on one that does not — which is what Paint has always done.
    var eraserClearsToTransparency: Bool { hasAlpha }

    enum Transform { case flipHorizontal, flipVertical, rotateLeft, rotateRight, invert }

    func apply(_ transform: Transform) {
        switch transform {
        case .rotateRight, .rotateLeft:
            checkpointWholeCanvas()            // a quarter turn swaps the sides over
        default:
            checkpoint()
            willTouchEverything()
        }
        switch transform {
        case .flipHorizontal: bitmap.flip(horizontally: true)
        case .flipVertical: bitmap.flip(horizontally: false)
        case .rotateRight: bitmap = bitmap.rotatedQuarterTurn(clockwise: true, fill: NSColor.white.cgColor)
        case .rotateLeft: bitmap = bitmap.rotatedQuarterTurn(clockwise: false, fill: NSColor.white.cgColor)
        case .invert: bitmap.invertColours()
        }
    }

    // MARK: - Regions

    func image(in rect: CGRect) -> CGImage? {
        bitmap.croppedImage(in: rect)
    }

    /// Undo the step a cancelled action checkpointed *and* put the dirty flag back to what
    /// it was before it. Cancelling a paste with Escape must leave a saved file saved —
    /// plain `undo()` marks every restored snapshot edited.
    func undoCancellingCheckpoint() {
        openPatch = nil
        if PaintDocument.verifiesUndo { _ = verificationStack.popLast() }
        history.cancelLastCheckpoint { step in
            switch step {
            case .patch(let patch): return patch.apply(to: bitmap)
            case .whole(let snapshot): adopt(snapshot); return true
            }
        }
        isDirty = wasDirtyBeforeCheckpoint
    }

    /// The operation is over: the step it recorded has stopped growing, so the history can
    /// be brought back inside its memory budget.
    func finishStep() { history.enforceBudget() }

    /// Drop the checkpoint an action recorded before discovering it changed nothing, and
    /// with it the dirty flag that checkpoint raised.
    func cancelCheckpoint() {
        history.discardLastCheckpoint()
        openPatch = nil
        if PaintDocument.verifiesUndo { _ = verificationStack.popLast() }
        isDirty = wasDirtyBeforeCheckpoint
    }

    func fillRegion(_ rect: CGRect, with color: NSColor) {
        willTouch(rect.integral)
        let ctx = bitmap.context
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect.integral)
        ctx.restoreGState()
    }

    /// Composite, never `.copy`: a pasted PNG can carry alpha, and copying it would punch
    /// transparency into a canvas the rest of the app assumes is opaque — which then
    /// survives into the exported file.
    func stamp(_ image: CGImage, at rect: CGRect) {
        willTouch(rect.integral)
        let ctx = bitmap.context
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: rect.integral)
        ctx.restoreGState()
        isDirty = true
    }
}
