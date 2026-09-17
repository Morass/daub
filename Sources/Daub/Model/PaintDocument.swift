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

    init(width: Int = 1024, height: Int = 768) {
        bitmap = Bitmap(width: width, height: height, fill: NSColor.white.cgColor)
    }

    init(image: CGImage, url: URL?) throws {
        bitmap = try Bitmap.checked(width: image.width, height: image.height, fill: NSColor.white.cgColor)
        bitmap.context.draw(image, in: bitmap.bounds)
        fileURL = url
    }

    /// Mark the pixels changed without opening an undo step. Painting inside one drag
    /// checkpoints once at mouse-down, so a save that lands mid-drag would otherwise
    /// clear the dirty flag while the airbrush is still spraying.
    func markDirty() { isDirty = true }

    // MARK: - History

    /// Call once immediately before a mutation that should be undoable as a single step.
    func checkpoint() {
        history.record(bitmap.makeImage())
        isDirty = true
    }

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
        bitmap = bitmap.resized(to: newWidth, newHeight, fill: fill.cgColor)
    }

    func scaleImage(to newWidth: Int, _ newHeight: Int) {
        checkpoint()
        guard let image = bitmap.makeImage() else { return }
        let out = Bitmap(width: newWidth, height: newHeight, fill: NSColor.white.cgColor)
        out.context.interpolationQuality = .high
        out.context.draw(image, in: out.bounds)
        bitmap = out
    }

    func clear(with color: NSColor) {
        checkpoint()
        bitmap.context.setFillColor(color.cgColor)
        bitmap.context.fill(bitmap.bounds)
    }

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

    /// Drop the checkpoint an action recorded before discovering it changed nothing.
    func cancelCheckpoint() { history.discardLastCheckpoint() }

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
