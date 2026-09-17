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

    init(image: CGImage, url: URL?) {
        bitmap = Bitmap(width: image.width, height: image.height, fill: NSColor.white.cgColor)
        bitmap.context.draw(image, in: bitmap.bounds)
        fileURL = url
    }

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
        guard let image = bitmap.makeImage() else { return }
        switch transform {
        case .flipHorizontal, .flipVertical:
            let ctx = bitmap.context
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            if transform == .flipHorizontal {
                ctx.translateBy(x: CGFloat(width), y: 0)
                ctx.scaleBy(x: -1, y: 1)
            } else {
                ctx.translateBy(x: 0, y: CGFloat(height))
                ctx.scaleBy(x: 1, y: -1)
            }
            ctx.draw(image, in: bitmap.bounds)
            ctx.restoreGState()

        case .rotateLeft, .rotateRight:
            let out = Bitmap(width: height, height: width, fill: NSColor.white.cgColor)
            let ctx = out.context
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            if transform == .rotateRight {
                ctx.translateBy(x: CGFloat(out.width), y: 0)
                ctx.rotate(by: .pi / 2)
            } else {
                ctx.translateBy(x: 0, y: CGFloat(out.height))
                ctx.rotate(by: -.pi / 2)
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            ctx.restoreGState()
            bitmap = out

        case .invert:
            bitmap.withRawPixels { base, w, h, rowBytes in
                for y in 0..<h {
                    let row = base + y * rowBytes
                    for x in 0..<w {
                        let p = row + x * 4
                        p[0] = 255 &- p[0]; p[1] = 255 &- p[1]; p[2] = 255 &- p[2]
                    }
                }
            }
        }
    }

    // MARK: - Regions

    func image(in rect: CGRect) -> CGImage? {
        bitmap.croppedImage(in: rect)
    }

    func fillRegion(_ rect: CGRect, with color: NSColor) {
        let ctx = bitmap.context
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect.integral)
        ctx.restoreGState()
    }

    func stamp(_ image: CGImage, at rect: CGRect) {
        let ctx = bitmap.context
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: rect.integral)
        ctx.restoreGState()
    }
}
