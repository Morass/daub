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

    func newDocument(width: Int = 1024, height: Int = 768) {
        guard confirmDiscardIfNeeded() else { return }
        replaceDocument(PaintDocument(width: width, height: height))
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
            replaceDocument(PaintDocument(image: image, url: url))
        } catch {
            present(error)
        }
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
        canvas?.commitFloatingSelection()
        guard let image = document.bitmap.makeImage() else { return false }
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
        canvas?.commitFloatingSelection()
        guard document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    // MARK: - Edit

    func undo() { if document.undo() { canvas?.documentDidChange(); didCommit() } }
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

    func clearCanvas() {
        canvas?.deselect()
        document.clear(with: secondaryNS)
        canvas?.documentDidChange()
        didCommit()
    }

    func resizeCanvas(width: Int, height: Int, scaleContents: Bool) {
        canvas?.commitFloatingSelection()
        if scaleContents {
            document.scaleImage(to: width, height)
        } else {
            document.resizeCanvas(to: width, height, fill: secondaryNS)
        }
        canvas?.documentDidChange()
        didCommit()
    }

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
