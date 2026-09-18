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

    /// Call once immediately before a mutation that should be undoable as a single step.
    func checkpoint() {
        history.record(bitmap.makeImage())
        wasDirtyBeforeCheckpoint = isDirty
        isDirty = true
    }

    /// What `isDirty` was before the checkpoint, so cancelling one can put it back: an
    /// action that turned out to change nothing must not leave a saved file looking edited.
    private var wasDirtyBeforeCheckpoint = false

    @discardableResult
    func undo() -> Bool {
        guard let previous = history.undo(current: bitmap.makeImage()) else { return false }
        adopt(previous)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = history.redo(current: bitmap.makeImage()) else { return false }
        adopt(next)
        return true
    }

    /// Restoring a snapshot may also restore a different canvas size (undoing a resize).
    private func adopt(_ image: CGImage) {
        if image.width != bitmap.width || image.height != bitmap.height {
            bitmap = Bitmap(width: image.width, height: image.height, fill: NSColor.white.cgColor)
        }
        bitmap.replace(with: image)
        isDirty = true
    }

    // MARK: - Whole-canvas operations

    func resizeCanvas(to newWidth: Int, _ newHeight: Int, fill: NSColor) {
        checkpoint()
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
        checkpoint()
        guard let image = bitmap.makeImage() else { return }
        let out = Bitmap(width: newWidth, height: newHeight,
                         fill: hasAlpha ? nil : NSColor.white.cgColor)
        out.context.interpolationQuality = .high
        out.context.draw(image, in: out.bounds)
        bitmap = out
    }

    func clear(with color: NSColor) {
        checkpoint()
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
                                           tolerance: tolerance, in: region)
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
                                           tolerance: tolerance, in: region)
        if changed == 0 { cancelCheckpoint() }
        return changed
    }

    /// Throw away everything outside `rect`. Cheap, and the operation a screenshot needs
    /// most often.
    func crop(to rect: CGRect) {
        let r = rect.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1, let cut = bitmap.croppedImage(in: r) else { return }
        checkpoint()
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
        checkpoint()
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
        let wasDirty = wasDirtyBeforeCheckpoint
        _ = undo()
        isDirty = wasDirty
    }

    /// Drop the checkpoint an action recorded before discovering it changed nothing, and
    /// with it the dirty flag that checkpoint raised.
    func cancelCheckpoint() {
        history.discardLastCheckpoint()
        isDirty = wasDirtyBeforeCheckpoint
    }

    func fillRegion(_ rect: CGRect, with color: NSColor) {
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
        let ctx = bitmap.context
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: rect.integral)
        ctx.restoreGState()
        isDirty = true
    }
}
