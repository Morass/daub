import AppKit
import DaubCore
import SwiftUI
import UniformTypeIdentifiers

/// Everything the chrome binds to. One instance per window.
@MainActor
final class Editor: ObservableObject {
    /// Daub is a single-window app; the app delegate needs the live editor to ask about
    /// unsaved work on quit, and there is no document architecture to route that through.
    private(set) static weak var current: Editor?
    @Published private(set) var document = PaintDocument()

    // Tool state
    @Published var tool: Tool = .pencil { didSet { toolDidChange(from: oldValue) } }
    @Published var primary: Color = .black
    @Published var secondary: Color = .white
    @Published var strokeWidth: Double = 3
    @Published var pencilSize: Double = 1
    @Published var eraserSize: Double = 12
    @Published var sprayRadius: Double = 14
    @Published var sprayDensity: Double = 20
    @Published var tolerance: Double = 0
    @Published var brushOpacity: Double = 1
    @Published var shapeStyle: ShapeFill = .outline
    @Published var antialias = true
    @Published var fontSize: Double = 28
    @Published var fontName: String = "Helvetica Neue"

    // View state
    @Published var zoom: CGFloat = 1
    @Published var showGrid = true
    @Published var showRulers = false

    // Derived / status
    @Published private(set) var revision = 0
    @Published var isDirty = false

    /// High-frequency readouts live on their own object; see CursorReadout.
    let readout = CursorReadout()

    weak var canvas: CanvasView?
    private var previousTool: Tool = .pencil

    init() { Editor.current = self }

    var primaryNS: NSColor { NSColor(primary) }
    var secondaryNS: NSColor { NSColor(secondary) }

    var canUndo: Bool { document.history.canUndo }
    var canRedo: Bool { document.history.canRedo }
    var canvasSize: CGSize { document.size }
    var windowTitle: String { document.displayName + (isDirty ? " — Edited" : "") }

    // MARK: - Commit boundary

    /// Refresh the chrome after a committed change. Strokes call this on mouse-up only.
    func didCommit() {
        isDirty = document.isDirty
        // The step is finished, so its patch has stopped growing and the history can be
        // measured honestly again.
        document.finishStep()
        revision &+= 1
    }

    private func toolDidChange(from old: Tool) {
        guard old != tool else { return }
        previousTool = old
        canvas?.toolWillChange()
    }

    /// The eyedropper snaps back to whatever you were using, which is what every modern
    /// editor does and what makes it usable mid-stroke.
    func revertToPreviousTool() {
        guard tool == .picker else { return }
        tool = previousTool == .picker ? .pencil : previousTool
    }

    // MARK: - File

    func newDocument(width: Int = 1024, height: Int = 768, transparent: Bool = false) {
        guard canvasIsAllowed(width: width, height: height) else { return }
        guard confirmDiscardIfNeeded() else { return }
        replaceDocument(PaintDocument(width: width, height: height, transparent: transparent))
    }

    func open() {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageFile.readableTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            let image = try ImageFile.read(url)
            replaceDocument(try PaintDocument(image: image, url: url))
        } catch {
            present(error)
        }
    }

    /// Turn whatever is on the clipboard into the picture, at its own size — the
    /// screenshot workflow: ⌃⇧⌘4, then ⇧⌘V, and the canvas already matches the shot.
    ///
    /// This is deliberately not the same as ⌘V. A paste lands *in* the picture you are
    /// working on; this one replaces it, so it asks about unsaved work exactly like Open.
    func newFromClipboard(from pasteboard: NSPasteboard = .general) {
        // Text still in its field, and a stroke still under the mouse, are work the
        // unsaved-work prompt below cannot see until they are in the picture.
        canvas?.endActiveDrag()
        canvas?.commitText()
        guard let image = ImageFile.readFromPasteboard(pasteboard) else {
            noImageOnClipboard()
            return
        }
        // Build the replacement *before* asking about unsaved work: an image too large to
        // open must not land after the user has already answered Discard, which would
        // leave the old picture on screen and marked clean.
        let new: PaintDocument
        do {
            new = try PaintDocument(image: image, url: nil)
        } catch {
            present(error)
            return
        }
        guard confirmDiscardIfNeeded() else { return }
        // Pixels that exist nowhere on disk: dirty from the first frame, so closing the
        // window asks before throwing a screenshot away.
        new.markDirty()
        replaceDocument(new)
        // A 5K screenshot at 1:1 shows a corner of itself. Fit it to the window —
        // shrinking only, so a small clipboard image is not blown up.
        canvas?.zoomToFitIfTooLarge()
    }

    private func noImageOnClipboard() {
        let alert = NSAlert()
        alert.messageText = "There is no picture on the clipboard."
        alert.informativeText = "Copy an image — or take a screenshot with ⌃⇧⌘4, which puts "
            + "it straight on the clipboard — and try again."
        alert.runModal()
    }

    @discardableResult
    func save() -> Bool {
        guard let url = document.fileURL, ImageFile.canWrite(url) else { return saveAs() }
        return write(to: url)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ImageFile.writableTypes
        panel.nameFieldStringValue = (document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        canvas?.endActiveDrag()
        canvas?.commitFloatingSelection()
        // JPEG has no alpha channel: a transparent canvas written straight out comes back
        // with black where the holes were, so flatten onto white first.
        let ext = url.pathExtension.lowercased()
        let needsFlattening = document.hasAlpha && (ext == "jpg" || ext == "jpeg")
        let image = needsFlattening
            ? document.bitmap.flattened(onto: NSColor.white.cgColor)
            : document.bitmap.makeImage()
        guard let image else { return false }
        do {
            try ImageFile.write(image, to: url)
            document.fileURL = url
            document.isDirty = false
            didCommit()
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func replaceDocument(_ new: PaintDocument) {
        document = new
        canvas?.documentDidChange()
        zoom = 1
        didCommit()
    }

    /// Unsaved work is the one thing an app this small must never lose silently.
    @discardableResult
    func confirmDiscardIfNeeded() -> Bool {
        // Do NOT commit the floating selection here: the user may still press Cancel, and
        // a committed float cannot be picked back up to carry on moving it.
        guard document.isDirty || canvas?.hasFloatingSelection == true else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()      // save() commits the float itself
        case .alertSecondButtonReturn:
            // The user has said the work is expendable. Recording that stops a second
            // prompt when closing the window also ends up quitting the app.
            document.isDirty = false
            isDirty = false
            return true
        default: return false
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    // MARK: - Edit

    /// A floating selection lives outside the history, so undoing with one on screen would
    /// throw those pixels away with nothing able to bring them back. Stamp it down first:
    /// the step being undone already holds the "before" snapshot, so ⌘Z still lands where
    /// the user expects — and ⇧⌘Z now returns the paste instead of an empty canvas.
    func undo() {
        canvas?.commitFloatingSelection()
        if document.undo() { canvas?.documentDidChange(); didCommit() }
    }
    func redo() { if document.redo() { canvas?.documentDidChange(); didCommit() } }

    // Cut/Copy/Paste/Select All are intentionally absent: they travel the responder
    // chain to whichever view has focus, so the text tool keeps its own clipboard.
    func deleteSelection() { canvas?.deleteSelection() }
    func deselect() { canvas?.deselect() }

    // MARK: - Image

    func apply(_ transform: PaintDocument.Transform) {
        canvas?.commitFloatingSelection()
        document.apply(transform)
        canvas?.documentDidChange()
        didCommit()
    }

    /// Knock the background colour out of the picture, so it can be saved as a PNG with
    /// real transparency. Uses the fill tolerance, which is the knob people already
    /// understand for "near enough to this colour".
    func makeBackgroundTransparent() {
        let region = canvas?.currentSelection
        canvas?.commitFloatingSelection()
        let changed = document.makeColourTransparent(secondaryNS, tolerance: Int(tolerance),
                                                     in: region)
        if changed == 0 {
            let alert = NSAlert()
            alert.messageText = "No pixels matched the background colour."
            alert.informativeText = "Daub knocks out the colour in the background well "
                + "(currently \(secondaryNS.accessibilityName)). Pick the colour you want "
                + "removed with the eyedropper — right-click sets the background — and raise "
                + "the Fill tolerance if the edges are soft."
            if region != nil {
                alert.informativeText += " Only the selected area was searched — deselect "
                    + "with ⌘D to knock the colour out of the whole picture."
            }
            alert.runModal()
            return
        }
        canvas?.documentDidChange()
        didCommit()
    }

    func replaceColourUnderBackground(with replacement: NSColor) {
        let region = canvas?.currentSelection
        canvas?.commitFloatingSelection()
        document.replaceColour(secondaryNS, with: replacement, tolerance: Int(tolerance),
                               in: region)
        canvas?.documentDidChange()
        didCommit()
    }

    func cropToSelection() {
        guard let rect = canvas?.currentSelection else { return }
        canvas?.commitFloatingSelection()
        document.crop(to: rect)
        canvas?.documentDidChange()
        didCommit()
    }

    func clearCanvas() {
        canvas?.deselect()
        document.clear(with: secondaryNS)
        canvas?.documentDidChange()
        didCommit()
    }

    func resizeCanvas(width: Int, height: Int, scaleContents: Bool) {
        guard canvasIsAllowed(width: width, height: height) else { return }
        canvas?.commitFloatingSelection()
        if scaleContents {
            document.scaleImage(to: width, height)
        } else {
            document.resizeCanvas(to: width, height, fill: secondaryNS)
        }
        canvas?.documentDidChange()
        didCommit()
    }

    /// `Bitmap` clamps each side but not the area, so the New and Resize sheets — where the
    /// numbers come from a user typing — are where the pixel limit has to be enforced.
    /// 32768 x 32768 is inside both side limits and is a 4 GB allocation.
    func canvasIsAllowed(width: Int, height: Int) -> Bool {
        if Bitmap.isAllocatable(width: width, height: height) { return true }
        guard Editor.showsAlerts else { return false }
        let alert = NSAlert()
        alert.messageText = "That picture would be too big."
        alert.informativeText = "Daub can work on up to \(Bitmap.maxPixels) pixels at once — "
            + "8192 × 8192, say — and at most \(Bitmap.maxDimension) on a side. "
            + "\(width) × \(height) is past that."
        alert.alertStyle = .warning
        alert.runModal()
        return false
    }

    /// Off in the headless self-test, where a modal alert would wait for a click that is
    /// never coming.
    static var showsAlerts = true

    // MARK: - View

    static let zoomSteps: [CGFloat] = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32]

    func zoomIn() { zoom = Editor.zoomSteps.first { $0 > zoom + 0.001 } ?? zoom }
    func zoomOut() { zoom = Editor.zoomSteps.last { $0 < zoom - 0.001 } ?? zoom }
    func actualSize() { zoom = 1 }
    func zoomToFit() { canvas?.zoomToFit() }

    func swapColours() {
        let p = primary
        primary = secondary
        secondary = p
    }
}
