import AppKit
import SwiftUI
import DaubCore

/// The pixel surface: hit testing, tools, live preview, selection.
///
/// This view owns its own redraw loop. SwiftUI is told about a change only at commit
/// boundaries (`editor.didCommit()`), never per mouse-drag — that is what keeps a drag
/// at display rate on a large canvas.
final class CanvasView: NSView {
    private unowned let editor: Editor
    private var doc: PaintDocument { editor.document }

    // MARK: Drag state

    private enum Drag {
        case none
        case stroke(last: CGPoint)
        case spray(point: CGPoint)
        case shape(start: CGPoint, current: CGPoint)
        case marquee(start: CGPoint, current: CGPoint)
        case moveSelection(grab: CGPoint, origin: CGPoint)
    }

    private struct Floating {
        var image: CGImage
        var rect: CGRect
    }

    private var drag: Drag = .none
    private var dragColour: NSColor = .black
    /// Which mouse button started this drag. Comparing NSColors would misfire whenever
    /// the foreground and background colours happen to be equal.
    private var dragIsSecondary = false
    private var selection: CGRect?
    private var floating: Floating?

    private var sprayTimer: Timer?
    private var antsTimer: Timer?
    private var antsPhase: CGFloat = 0
    private var rng = SystemRandomNumberGenerator()
    private var textField: NSTextField?

    /// Clone stamp: ⌥-click sets the source. The snapshot is taken at mouse-down so the
    /// tool copies the picture as it was, not the paint it is laying down — otherwise a
    /// stroke that crosses its own source smears into a feedback loop.
    /// Whether the lift that created the current floating selection actually changed the
    /// picture. A move clears the pixels it lifted, so discarding it has to undo that; a
    /// ⌥-drag duplicate and a paste change nothing, so discarding them must throw the
    /// checkpoint away instead — otherwise ⌥-drag then Delete leaves an undo step that
    /// undoes nothing and a document marked edited.
    private var floatingChangedPixels = false

    private var cloneSource: CGPoint?
    private var cloneOffset: CGSize?
    private var cloneSnapshot: CGImage?

    var currentSelection: CGRect? { floating?.rect ?? selection }

    // MARK: Init

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: CGRect(origin: .zero, size: editor.document.size))
        wantsLayer = true
        layer?.magnificationFilter = .nearest
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }          // match CoreGraphics: origin bottom-left
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var zoom: CGFloat { editor.zoom }
    var canvasPixelSize: CGSize { doc.size }
    var scaledSize: CGSize { CGSize(width: doc.size.width * zoom, height: doc.size.height * zoom) }

    // MARK: - Coordinates

    /// Shapes stroke in the dragging button's colour and fill with the other one.
    private var shapeFillColour: NSColor {
        dragIsSecondary ? editor.primaryNS : editor.secondaryNS
    }

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / zoom, y: p.y / zoom)
    }

    private func pixel(_ p: CGPoint) -> (x: Int, y: Int) {
        (Int(floor(p.x)), Int(floor(p.y)))
    }

    private func viewRect(fromCanvas r: CGRect) -> CGRect {
        CGRect(x: r.minX * zoom, y: r.minY * zoom, width: r.width * zoom, height: r.height * zoom)
    }

    private func invalidate(canvasRect r: CGRect) {
        setNeedsDisplay(viewRect(fromCanvas: r).insetBy(dx: -2 * zoom - 2, dy: -2 * zoom - 2))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none

        if doc.hasAlpha { drawCheckerboard(ctx, in: dirtyRect) }

        // `liveImage` reads through to the bitmap's buffer; cropping it to the dirty
        // region means a stroke blits the pixels it touched, not the whole canvas.
        if let image = doc.bitmap.liveImage {
            let canvasRect = CGRect(x: dirtyRect.minX / zoom, y: dirtyRect.minY / zoom,
                                    width: dirtyRect.width / zoom, height: dirtyRect.height / zoom)
            let clip = canvasRect.integral.intersection(doc.bounds)
            if clip.width >= 1, clip.height >= 1, clip != doc.bounds,
               let part = doc.bitmap.croppedLiveImage(in: clip) {
                ctx.draw(part, in: viewRect(fromCanvas: clip))
            } else {
                ctx.draw(image, in: CGRect(origin: .zero, size: scaledSize))
            }
        }

        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)

        if let floating {
            ctx.interpolationQuality = .none
            ctx.draw(floating.image, in: floating.rect)
        }

        if case let .shape(start, current) = drag, editor.tool == .gradient {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1 / zoom)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 4 / zoom])
            ctx.move(to: start)
            ctx.addLine(to: current)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        } else if case let .shape(start, current) = drag, let kind = editor.tool.shapeKind {
            Shapes.draw(kind, in: ctx, from: start, to: current,
                        stroke: dragColour.cgColor,
                        fill: shapeFillColour.cgColor,
                        style: editor.shapeStyle,
                        lineWidth: editor.strokeWidth,
                        antialias: editor.antialias)
        }
        ctx.restoreGState()

        if editor.showGrid && zoom >= 8 { drawPixelGrid(ctx) }

        if case let .marquee(start, current) = drag {
            drawAnts(ctx, rect: CGRect.normalised(from: start, to: current))
        } else if let rect = floating?.rect ?? selection {
            drawAnts(ctx, rect: rect)
        }
    }

    /// The universal "this is nothing, not white" backdrop.
    private func drawCheckerboard(_ ctx: CGContext, in rect: CGRect) {
        let square: CGFloat = 8
        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
        ctx.setFillColor(NSColor(white: 0.86, alpha: 1).cgColor)
        let x0 = (rect.minX / square).rounded(.down) * square
        let y0 = (rect.minY / square).rounded(.down) * square
        var y = y0
        while y < rect.maxY {
            var x = x0
            while x < rect.maxX {
                if Int((x / square).rounded(.down) + (y / square).rounded(.down)) % 2 == 0 {
                    ctx.fill(CGRect(x: x, y: y, width: square, height: square))
                }
                x += square
            }
            y += square
        }
        ctx.restoreGState()
    }

    private func drawPixelGrid(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.12).cgColor)
        let size = scaledSize
        var x = zoom
        while x < size.width {
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height))
            x += zoom
        }
        var y = zoom
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y))
            y += zoom
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Marching ants: white under, black dashes over, so the marquee is visible on any artwork.
    private func drawAnts(_ ctx: CGContext, rect: CGRect) {
        let r = viewRect(fromCanvas: rect.integral).insetBy(dx: -0.5, dy: -0.5)
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(r)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineDash(phase: antsPhase, lengths: [4, 4])
        ctx.stroke(r)
        ctx.restoreGState()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) { begin(event, secondary: false) }
    override func mouseDragged(with event: NSEvent) { continueDrag(event) }
    override func mouseUp(with event: NSEvent) { endDrag(event) }

    // Right-drag paints the secondary colour, exactly as classic Paint does.
    override func rightMouseDown(with event: NSEvent) { begin(event, secondary: true) }
    override func rightMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func rightMouseUp(with event: NSEvent) { endDrag(event) }

    override func mouseMoved(with event: NSEvent) { reportCursor(canvasPoint(event)) }
    override func mouseExited(with event: NSEvent) { editor.readout.pixel = nil }

    private func reportCursor(_ p: CGPoint) {
        let px = pixel(p)
        guard px.x >= 0, px.y >= 0, px.x < doc.width, px.y < doc.height else {
            editor.readout.pixel = nil
            return
        }
        // Report in top-left origin, which is what every other image tool shows.
        editor.readout.pixel = CGPoint(x: px.x, y: doc.height - 1 - px.y)
    }

    private func begin(_ event: NSEvent, secondary: Bool) {
        window?.makeFirstResponder(self)
        commitText()
        let p = canvasPoint(event)
        dragIsSecondary = secondary
        dragColour = secondary ? editor.secondaryNS : editor.primaryNS
        let colour = dragColour

        switch editor.tool {
        case .pencil, .brush, .eraser:
            commitFloatingSelection()
            doc.checkpoint()
            drag = .stroke(last: p)
            paintSegment(from: p, to: p)

        case .airbrush:
            commitFloatingSelection()
            doc.checkpoint()
            drag = .spray(point: p)
            sprayPuff(at: p)
            sprayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, case let .spray(point) = self.drag else { return }
                    self.sprayPuff(at: point)
                }
            }

        case .fill:
            commitFloatingSelection()
            let px = pixel(p)
            // Convert the colour *before* opening an undo step: a colour that cannot be
            // converted would otherwise leave a checkpoint behind that undoes nothing.
            guard let rgba = RGBA(colour.cgColor) else { return }
            doc.checkpoint()
            if let dirty = FloodFill.fill(doc.bitmap, x: px.x, y: px.y, with: rgba,
                                          tolerance: Int(editor.tolerance),
                                          willTouch: { [doc] span in doc.willTouch(span) }) {
                doc.markDirty()
                invalidate(canvasRect: dirty)
            } else {
                doc.cancelCheckpoint()          // clicked a region already that colour
            }
            editor.didCommit()

        case .picker:
            let px = pixel(p)
            let c = doc.bitmap.pixel(x: px.x, y: px.y)
            let picked = Color(nsColor: NSColor(cgColor: c.cgColor) ?? .black)
            if secondary { editor.secondary = picked } else { editor.primary = picked }
            editor.revertToPreviousTool()

        case .text:
            commitFloatingSelection()
            beginText(at: p)

        case .gradient, .line, .rectangle, .roundedRectangle, .ellipse:
            commitFloatingSelection()
            drag = .shape(start: p, current: p)

        case .clone:
            commitFloatingSelection()
            if event.modifierFlags.contains(.option) {
                cloneSource = p
                cloneOffset = nil
                return
            }
            guard let source = cloneSource else {
                NSSound.beep()          // nothing to clone from yet
                return
            }
            doc.checkpoint()
            cloneOffset = CGSize(width: p.x - source.x, height: p.y - source.y)
            cloneSnapshot = doc.bitmap.makeImage()
            drag = .stroke(last: p)
            cloneDab(at: p)

        case .colourReplace:
            // Scoped to the selection when there is one, which is the only way to recolour
            // one button and not every pixel of that colour in the picture.
            let region = currentSelection
            // Test the click before committing anything: a click outside the selection is a
            // miss, and a miss must not stamp a floating selection down as a side effect.
            guard region == nil || region!.contains(p) else { NSSound.beep(); return }
            commitFloatingSelection()
            let px = pixel(p)
            let under = doc.bitmap.pixel(x: px.x, y: px.y)
            guard let underColour = NSColor(cgColor: under.cgColor) else { return }
            let changed = doc.replaceColour(underColour, with: colour,
                                            tolerance: Int(editor.tolerance), in: region)
            if changed == 0 { NSSound.beep(); return }   // already that colour: no undo step
            needsDisplay = true
            editor.didCommit()

        case .select:
            if let rect = floating?.rect ?? selection, rect.contains(p) {
                liftSelectionIfNeeded(rect, leavingCopy: event.modifierFlags.contains(.option))
                drag = .moveSelection(grab: p, origin: floating?.rect.origin ?? rect.origin)
            } else {
                commitFloatingSelection()
                selection = nil
                drag = .marquee(start: p, current: p)
                needsDisplay = true
            }
        }
    }

    private func continueDrag(_ event: NSEvent) {
        let p = canvasPoint(event)
        reportCursor(p)
        switch drag {
        case .stroke(let last):
            paintSegment(from: last, to: p)
            drag = .stroke(last: p)

        case .spray:
            drag = .spray(point: p)
            sprayPuff(at: p)

        case .shape(let start, let previous):
            let end = event.modifierFlags.contains(.shift) ? constrain(start, p) : p
            let old = CGRect.normalised(from: start, to: previous)
            drag = .shape(start: start, current: end)
            let pad = editor.strokeWidth + 2
            invalidate(canvasRect: old.union(CGRect.normalised(from: start, to: end))
                .insetBy(dx: -pad, dy: -pad))

        case .marquee(let start, _):
            let old = CGRect.normalised(from: start, to: p)
            drag = .marquee(start: start, current: p)
            invalidate(canvasRect: old.union(CGRect.normalised(from: start, to: p)))
            editor.readout.selection = CGRect.normalised(from: start, to: p).integral.size

        case .moveSelection(let grab, let origin):
            guard var f = floating else { return }
            let old = f.rect
            f.rect.origin = CGPoint(x: (origin.x + p.x - grab.x).rounded(),
                                    y: (origin.y + p.y - grab.y).rounded())
            floating = f
            invalidate(canvasRect: old.union(f.rect))

        case .none:
            break
        }
    }

    private func endDrag(_ event: NSEvent) {
        let p = canvasPoint(event)
        switch drag {
        case .shape(let start, _):
            let end = event.modifierFlags.contains(.shift) ? constrain(start, p) : p
            if editor.tool == .gradient {
                applyGradient(from: start, to: end)
            } else if let kind = editor.tool.shapeKind {
                doc.checkpoint()
                let reach = editor.strokeWidth + 4
                doc.willTouch(CGRect.normalised(from: start, to: end).insetBy(dx: -reach, dy: -reach))
                Shapes.draw(kind, in: doc.context, from: start, to: end,
                            stroke: dragColour.cgColor,
                            fill: shapeFillColour.cgColor,
                            style: editor.shapeStyle,
                            lineWidth: editor.strokeWidth,
                            antialias: editor.antialias)
            }
            drag = .none
            needsDisplay = true
            editor.didCommit()

        case .marquee(let start, _):
            let rect = CGRect.normalised(from: start, to: p).integral.intersection(doc.bounds)
            selection = (rect.width >= 1 && rect.height >= 1) ? rect : nil
            editor.readout.selection = selection?.size
            drag = .none
            startAnts()
            needsDisplay = true

        case .spray:
            sprayTimer?.invalidate(); sprayTimer = nil
            drag = .none
            editor.didCommit()

        case .stroke:
            drag = .none
            editor.didCommit()

        case .moveSelection:
            drag = .none
            editor.didCommit()

        case .none:
            break
        }
    }

    /// Shift constrains: lines to 45°, rectangles and ellipses to squares and circles.
    private func constrain(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        if editor.tool == .line {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let r = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + cos(angle) * r, y: start.y + sin(angle) * r)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    // MARK: - Painting primitives

    /// Linear gradient from the foreground colour to the background colour along the drag,
    /// clipped to the selection when there is one. Ten lines of CoreGraphics, and it is the
    /// cheapest way to get a usable backdrop in a paint app with no layers.
    private func applyGradient(from a: CGPoint, to b: CGPoint) {
        let space = CGColorSpaceCreateDeviceRGB()
        let start = editor.primaryNS.withAlphaComponent(editor.brushOpacity)
        let end = editor.secondaryNS.withAlphaComponent(editor.brushOpacity)
        guard let from = start.usingColorSpace(.sRGB)?.cgColor,
              let to = end.usingColorSpace(.sRGB)?.cgColor,
              let gradient = CGGradient(colorsSpace: space, colors: [from, to] as CFArray,
                                        locations: [0, 1])
        else { return }

        doc.checkpoint()
        doc.willTouch(selection?.integral ?? doc.bounds)
        let ctx = doc.context
        ctx.saveGState()
        if let selection { ctx.clip(to: selection.integral) }
        ctx.drawLinearGradient(gradient, start: a, end: b,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        doc.markDirty()
        needsDisplay = true
    }

    /// One round dab of cloned pixels: clip to a circle, draw the snapshot shifted by the
    /// source offset, so the brush reveals the other part of the picture.
    private func cloneDab(at p: CGPoint) {
        guard let snapshot = cloneSnapshot, let offset = cloneOffset else { return }
        let radius = max(1, editor.strokeWidth) / 2
        let dab = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        doc.willTouch(dab.insetBy(dx: -2, dy: -2))
        let ctx = doc.context
        ctx.saveGState()
        ctx.addEllipse(in: dab)
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.draw(snapshot, in: CGRect(x: offset.width, y: offset.height,
                                      width: CGFloat(doc.width), height: CGFloat(doc.height)))
        ctx.restoreGState()
        doc.markDirty()
        invalidate(canvasRect: dab)
    }

    private func paintSegment(from a: CGPoint, to b: CGPoint) {
        if editor.tool == .clone {
            // Dab along the segment so a fast drag does not leave gaps.
            let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / max(1, editor.strokeWidth / 3)))
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                cloneDab(at: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            return
        }
        switch editor.tool {
        case .pencil, .eraser:
            let erasing = editor.tool == .eraser
            let colour = erasing ? editor.secondaryNS : dragColour
            var rgba = RGBA(colour.cgColor)
            if erasing && doc.eraserClearsToTransparency {
                rgba = RGBA(r: 0, g: 0, b: 0, a: 0)     // rub through to nothing
            }
            guard let rgba else { return }
            let size = Int(erasing ? editor.eraserSize : editor.pencilSize)
            doc.willTouch(CGRect.normalised(from: a, to: b)
                .insetBy(dx: -CGFloat(size) - 2, dy: -CGFloat(size) - 2))
            let dirty = Raster.line(doc.bitmap, from: pixel(a), to: pixel(b), size: max(1, size), color: rgba)
            doc.markDirty()
            invalidate(canvasRect: dirty)

        default:
            let reach = editor.strokeWidth + 2
            doc.willTouch(CGRect.normalised(from: a, to: b).insetBy(dx: -reach, dy: -reach))
            let ctx = doc.context
            ctx.saveGState()
            ctx.setShouldAntialias(editor.antialias)
            ctx.setStrokeColor(dragColour.withAlphaComponent(editor.brushOpacity).cgColor)
            ctx.setLineWidth(editor.strokeWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
            ctx.restoreGState()
            doc.markDirty()
            let pad = editor.strokeWidth
            invalidate(canvasRect: CGRect.normalised(from: a, to: b).insetBy(dx: -pad, dy: -pad))
        }
    }

    private func sprayPuff(at p: CGPoint) {
        guard let rgba = RGBA(dragColour.cgColor) else { return }
        let px = pixel(p)
        let reach = editor.sprayRadius + 2
        doc.willTouch(CGRect(x: p.x - reach, y: p.y - reach, width: reach * 2, height: reach * 2))
        let dirty = Raster.spray(doc.bitmap, x: px.x, y: px.y,
                                 radius: Int(editor.sprayRadius),
                                 density: Int(editor.sprayDensity),
                                 color: rgba, using: &rng)
        doc.markDirty()
        invalidate(canvasRect: dirty)
    }

    // MARK: - Selection

    /// - Parameter leavingCopy: ⌥-drag duplicates instead of moving, so the pixels under
    ///   the selection stay put and only the floating copy travels.
    private func liftSelectionIfNeeded(_ rect: CGRect, leavingCopy: Bool = false) {
        guard floating == nil else { return }
        doc.checkpoint()
        guard let image = doc.image(in: rect) else { return }
        if !leavingCopy { doc.fillRegion(rect, with: editor.secondaryNS) }
        floatingChangedPixels = !leavingCopy
        floating = Floating(image: image, rect: rect.integral)
        selection = nil
        needsDisplay = true
    }

    /// Throw the floating selection away.
    ///
    /// - Parameter restoringPixels: Escape puts the picture back how it was, so a move has to
    ///   undo the lift that cleared its source. Delete does not: for a move the cleared
    ///   source *is* the deletion. Either way a float that never changed a pixel — a paste,
    ///   or an ⌥-drag duplicate — drops its checkpoint instead, so discarding it leaves no
    ///   undo step and no edited flag behind.
    private func discardFloatingSelection(restoringPixels: Bool) {
        guard floating != nil else { return }
        floating = nil
        if !floatingChangedPixels {
            doc.cancelCheckpoint()
        } else if restoringPixels {
            doc.undoCancellingCheckpoint()
            // The undo may have put back a smaller canvas (a paste that grew it), so the
            // view has to be resized to match before it draws.
            applyZoom()
        }
        floatingChangedPixels = false
        needsDisplay = true
    }

    func commitFloatingSelection() {
        guard let f = floating else { return }
        doc.stamp(f.image, at: f.rect)
        floating = nil
        floatingChangedPixels = false
        selection = f.rect.intersection(doc.bounds)
        needsDisplay = true
        editor.didCommit()
    }

    override func selectAll(_ sender: Any?) { selectWholeCanvas() }
    @objc func copy(_ sender: Any?) { copySelection() }
    @objc func cut(_ sender: Any?) { cutSelection() }
    @objc func paste(_ sender: Any?) { pasteFromClipboard() }
    @objc func delete(_ sender: Any?) { deleteSelection() }

    func selectWholeCanvas() {
        commitFloatingSelection()
        selection = doc.bounds
        editor.readout.selection = doc.size
        startAnts()
        needsDisplay = true
    }

    func deselect() {
        commitFloatingSelection()
        selection = nil
        editor.readout.selection = nil
        stopAnts()
        needsDisplay = true
    }

    func deleteSelection() {
        if floating != nil {
            discardFloatingSelection(restoringPixels: false)   // a move already cleared its source
            selection = nil
            editor.readout.selection = nil
            needsDisplay = true
            editor.didCommit()
            return
        }
        guard let rect = selection else { return }
        doc.checkpoint()
        doc.fillRegion(rect, with: editor.secondaryNS)
        selection = nil
        editor.readout.selection = nil
        needsDisplay = true
        editor.didCommit()
    }

    func copySelection() {
        let image: CGImage? = floating?.image ?? selection.flatMap { doc.image(in: $0) } ?? doc.bitmap.makeImage()
        guard let image else { return }
        ImageFile.writeToPasteboard(image)
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    func pasteFromClipboard(from pasteboard: NSPasteboard = .general) {
        guard let image = ImageFile.readFromPasteboard(pasteboard) else { return }
        // ⌘V can arrive mid-drag (trackpad in one hand, keyboard in the other). Finish the
        // drag first: switching tool below would otherwise leave mouse-up looking for a
        // shape kind the tool no longer has, and an airbrush timer spraying into a canvas
        // that is about to be resized.
        endActiveDrag()
        commitFloatingSelection()
        // Switch tools *first*: changing tool commits any floating selection, which would
        // otherwise stamp the pasted image the instant it was created.
        editor.tool = .select
        doc.checkpoint()
        // A screenshot is nearly always bigger than the canvas it is pasted onto, and a
        // paste that silently loses everything past the edge is the worst way to find that
        // out. Grow the canvas to hold it instead — inside the same undo step, so one ⌘Z
        // puts both the pixels and the canvas size back.
        let incoming = CGSize(width: image.width, height: image.height)
        let grown = CanvasFit.grown(canvas: doc.size, toFit: incoming)
        let didGrow = grown != doc.size
        if didGrow {
            // The canvas is about to change size, so this step cannot be a patch: swap it
            // for a snapshot of the picture as it is now, before the growth.
            doc.promoteCheckpointToWholeCanvas()
            doc.growCanvas(to: grown, fill: editor.secondaryNS)
            applyZoom()
        }
        let rect = CGRect(x: 0, y: CGFloat(doc.height - image.height),
                          width: CGFloat(image.width), height: CGFloat(image.height))
        // A plain paste has not touched the canvas — but growing it has, and that must be
        // undone if the paste is then cancelled with Escape.
        floatingChangedPixels = didGrow
        floating = Floating(image: image, rect: rect)
        editor.readout.selection = rect.size
        startAnts()
        needsDisplay = true
        editor.didCommit()
        if !didGrow, !CanvasFit.fits(incoming, in: doc.size) { warnPasteIsClipped(incoming) }
    }

    /// The one case growth cannot solve: an image whose bounding canvas would be past what
    /// Daub will allocate. It is pasted as far as it goes; saying so beats a silent crop.
    private func warnPasteIsClipped(_ incoming: CGSize) {
        let alert = NSAlert()
        alert.messageText = "The clipboard picture is too large to fit on this canvas."
        alert.informativeText = "It is \(Int(incoming.width)) x \(Int(incoming.height)), and a canvas big "
            + "enough to hold it would be past Daub's limit of \(Bitmap.maxPixels) pixels. "
            + "What fits has been pasted; the rest is not there. Crop or shrink the picture "
            + "before copying it if you need all of it."
        alert.runModal()
    }

    private func startAnts() {
        guard antsTimer == nil else { return }
        antsTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.antsPhase += 1
                if let rect = self.floating?.rect ?? self.selection {
                    self.invalidate(canvasRect: rect)
                } else {
                    self.stopAnts()
                }
            }
        }
    }

    private func stopAnts() {
        antsTimer?.invalidate()
        antsTimer = nil
    }

    // MARK: - Text

    private func beginText(at p: CGPoint) {
        let field = NSTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont(name: editor.fontName, size: editor.fontSize * zoom)
            ?? .systemFont(ofSize: editor.fontSize * zoom)
        field.textColor = editor.primaryNS
        field.placeholderString = "Type, then ⏎"
        field.delegate = self
        let height = (field.font?.ascender ?? 0) - (field.font?.descender ?? 0) + 6
        field.frame = CGRect(x: p.x * zoom, y: p.y * zoom, width: 260, height: height)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    /// Bake the overlay text into the bitmap at the point it was typed.
    func commitText() {
        guard let field = textField else { return }
        textField = nil
        defer { field.removeFromSuperview(); window?.makeFirstResponder(self) }
        let string = field.stringValue
        guard !string.isEmpty else { return }

        doc.checkpoint()
        let font = NSFont(name: editor.fontName, size: editor.fontSize) ?? .systemFont(ofSize: editor.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: editor.primaryNS]

        // The cell insets its text inside the field's frame, and reports that rect in its
        // own flipped space. Aligning the two bounding boxes is the difference between
        // text that lands where it was typed and text a line-height off.
        var textRect = field.bounds
        if let cell = field.cell { textRect = cell.titleRect(forBounds: field.bounds) }
        let insetX = textRect.minX
        let insetYFromBottom = field.bounds.height - textRect.maxY
        let origin = CGPoint(x: (field.frame.minX + insetX) / zoom,
                             y: (field.frame.minY + insetYFromBottom) / zoom)

        // Generous on purpose: a glyph can overshoot its typographic box, and a rectangle
        // that is too small here means text that Undo cannot fully remove.
        let drawn = (string as NSString).size(withAttributes: attributes)
        let slack = editor.fontSize + 8
        doc.willTouch(CGRect(x: origin.x, y: origin.y, width: drawn.width, height: drawn.height)
            .insetBy(dx: -slack, dy: -slack))

        let ns = NSGraphicsContext(cgContext: doc.context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        (string as NSString).draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        needsDisplay = true
        editor.didCommit()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:                                   // Escape
            if floating != nil {
                discardFloatingSelection(restoringPixels: true)
                editor.didCommit()
            }
            deselect()
        case 51, 117:                              // Delete / Forward-delete
            deleteSelection()
        case 123, 124, 125, 126:                   // Arrows nudge a floating selection
            guard var f = floating else { return super.keyDown(with: event) }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let old = f.rect
            switch event.keyCode {
            case 123: f.rect.origin.x -= step
            case 124: f.rect.origin.x += step
            case 125: f.rect.origin.y -= step
            default:  f.rect.origin.y += step
            }
            floating = f
            invalidate(canvasRect: old.union(f.rect))
        default:
            guard handleShortcut(event) else { return super.keyDown(with: event) }
        }
    }

    /// Bare-letter shortcuts, handled here rather than as menu key equivalents so that
    /// typing into the text tool's field is never hijacked by the toolbox.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if let tool = Tool.allCases.first(where: { $0.shortcut.character == key }) {
            editor.tool = tool
            return true
        }
        switch key {
        case "x": editor.swapColours()
        case "[": adjustSize(by: -1)
        case "]": adjustSize(by: +1)
        default: return false
        }
        return true
    }

    private func adjustSize(by delta: Double) {
        switch editor.tool.sizeKnob {
        case .pencil: editor.pencilSize = max(1, min(16, editor.pencilSize + delta))
        case .stroke: editor.strokeWidth = max(1, min(48, editor.strokeWidth + delta))
        case .eraser: editor.eraserSize = max(1, min(96, editor.eraserSize + delta))
        case .spray: editor.sprayRadius = max(2, min(80, editor.sprayRadius + delta))
        case .none: break
        }
    }

    // MARK: - Lifecycle hooks used by Editor

    func toolWillChange() {
        commitText()
        if editor.tool != .select { commitFloatingSelection(); deselect() }
    }

    /// Stop anything still painting. A timer that outlives its document keeps spraying
    /// into a bitmap nobody is looking at — and, after a save, does it without marking
    /// the file dirty again.
    func endActiveDrag() {
        sprayTimer?.invalidate()
        sprayTimer = nil
        drag = .none
    }

    var hasFloatingSelection: Bool { floating != nil }

    func documentDidChange() {
        endActiveDrag()
        floating = nil
        selection = nil
        stopAnts()
        editor.readout.selection = nil
        applyZoom()
        needsDisplay = true
    }

    func applyZoom() {
        let size = scaledSize
        setFrameSize(size)
        (superview as? CanvasContainerView)?.refreshLayout()
        needsDisplay = true
    }

    /// Shrink-to-fit: used after a whole picture arrives from the clipboard, where the
    /// common case is a screenshot far bigger than the window. A picture that already fits
    /// is left at whatever zoom it was, never magnified.
    func zoomToFitIfTooLarge() {
        guard let clip = enclosingScrollView?.contentView.bounds.size, clip.width > 40 else { return }
        let margin: CGFloat = 40
        let fit = min((clip.width - margin) / doc.size.width, (clip.height - margin) / doc.size.height)
        guard fit < 1 else { return }
        // Round *down*: rounding to the nearest percent can land above the fit and leave a
        // sliver of the picture outside the window, which is exactly what this avoids.
        editor.zoom = max(0.01, (fit * 100).rounded(.down) / 100)
    }

    func zoomToFit() {
        guard let clip = enclosingScrollView?.contentView.bounds.size, clip.width > 40 else { return }
        let margin: CGFloat = 40
        let fit = min((clip.width - margin) / doc.size.width, (clip.height - margin) / doc.size.height)
        editor.zoom = max(0.05, min(32, (fit * 100).rounded() / 100))
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor = switch editor.tool {
        case .text: .iBeam
        case .select: .crosshair
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self))
    }

    override func magnify(with event: NSEvent) {
        let next = editor.zoom * (1 + event.magnification)
        editor.zoom = max(0.25, min(32, next))
    }
}

extension CanvasView: NSTextFieldDelegate {
    /// Return commits the text. `controlTextDidEndEditing` alone is not enough — the field
    /// does not always end editing on Return inside a plain NSView — and the action/target
    /// route it replaced fired inconsistently, which is why typed text only appeared once
    /// the tool was switched.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitText()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            textField?.removeFromSuperview()
            textField = nil
            window?.makeFirstResponder(self)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }
}

extension CGRect {
    static func normalised(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
