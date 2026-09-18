import AppKit
import DaubCore

/// End-to-end checks that drive the real app through the real clipboard, because the
/// paste path lives in the app target where `swift test` cannot reach it.
///
///     DAUB_SELFTEST=clipboard build/Daub.app/Contents/MacOS/Daub
///
/// Prints one line per check and exits non-zero on the first failure. `make selftest`
/// wraps it. It drives a private pasteboard, not the system clipboard, so running it does
/// not throw away whatever the user had copied.
@MainActor
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["DAUB_SELFTEST"] == "clipboard" else { return }
        // One hop through the run loop so SwiftUI has built the chrome and the canvas view
        // exists — the paste path goes through it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run() }
    }

    private static var failures = 0

    /// A board of our own. Everything under test takes the pasteboard as a parameter for
    /// exactly this reason.
    private static let board = NSPasteboard(name: NSPasteboard.Name("Daub.selftest"))

    private static func run() {
        guard let editor = Editor.current, let canvas = editor.canvas else {
            note("FAIL  no editor or canvas")
            exit(1)
        }

        // 1. A whole picture imported from the clipboard sizes the canvas to it.
        put(image(width: 2400, height: 1600, colour: .systemBlue))
        editor.newFromClipboard(from: board)
        check(editor.canvasSize == CGSize(width: 2400, height: 1600),
              "New from Clipboard sizes the canvas to the clipboard image",
              "got \(editor.canvasSize)")
        check(editor.zoom < 1, "a picture larger than the window is zoomed to fit",
              "zoom \(editor.zoom)")
        check(editor.isDirty, "imported pixels count as unsaved work", "not dirty")
        check(!editor.document.hasAlpha,
              "a picture with no transparency comes in opaque", "hasAlpha true")

        // 2. Pasting into a smaller canvas grows the canvas instead of clipping.
        reset(editor, width: 1024, height: 768)
        put(image(width: 2000, height: 1500, colour: .systemRed))
        canvas.pasteFromClipboard(from: board)
        check(editor.canvasSize == CGSize(width: 2000, height: 1500),
              "a paste larger than the canvas grows the canvas", "got \(editor.canvasSize)")
        check(canvas.hasFloatingSelection, "the paste is floating, ready to be dragged", "no float")

        canvas.commitFloatingSelection()
        let topLeft = editor.document.bitmap.pixel(x: 0, y: editor.document.height - 1)
        check(topLeft.r > 200 && topLeft.g < 120,
              "the pasted image lands in the top-left corner", "corner pixel \(topLeft)")

        // 3. Grow and paste undo together, as one step.
        editor.undo()
        check(editor.canvasSize == CGSize(width: 1024, height: 768),
              "one undo puts back both the pixels and the canvas size", "got \(editor.canvasSize)")
        let restored = editor.document.bitmap.pixel(x: 0, y: editor.document.height - 1)
        check(restored.r > 200 && restored.g > 200 && restored.b > 200,
              "the canvas is white again after the undo", "corner pixel \(restored)")

        // 4. Redo after that undo brings the pasted picture back, canvas and all.
        editor.redo()
        check(editor.canvasSize == CGSize(width: 2000, height: 1500),
              "redo puts the grown canvas back", "got \(editor.canvasSize)")
        let redone = editor.document.bitmap.pixel(x: 0, y: editor.document.height - 1)
        check(redone.r > 200 && redone.g < 120,
              "redo puts the pasted pixels back, not an empty canvas", "corner pixel \(redone)")

        // 5. Escape cancels a paste that grew the canvas — including the growth.
        reset(editor, width: 1024, height: 768)
        put(image(width: 2000, height: 1500, colour: .systemRed))
        canvas.pasteFromClipboard(from: board)
        canvas.keyDown(with: escapeKey())
        check(editor.canvasSize == CGSize(width: 1024, height: 768),
              "Escape after a grown paste puts the canvas size back",
              "got \(editor.canvasSize)")
        let cancelled = editor.document.bitmap.pixel(x: 0, y: editor.document.height - 1)
        check(cancelled.r > 200 && cancelled.g > 200 && cancelled.b > 200,
              "Escape leaves no pasted pixels behind", "corner pixel \(cancelled)")

        // 6. Undoing with the paste still floating keeps it in the history.
        reset(editor, width: 1024, height: 768)
        put(image(width: 1400, height: 900, colour: .systemRed))
        canvas.pasteFromClipboard(from: board)
        editor.undo()
        check(editor.canvasSize == CGSize(width: 1024, height: 768),
              "undo while the paste is still floating removes it", "got \(editor.canvasSize)")
        editor.redo()
        check(editor.canvasSize == CGSize(width: 1400, height: 900),
              "and redo brings that floating paste back", "got \(editor.canvasSize)")

        // 7. Cancelling a paste leaves a saved picture saved.
        reset(editor, width: 1024, height: 768)
        put(image(width: 2000, height: 1500, colour: .systemRed))
        canvas.pasteFromClipboard(from: board)
        canvas.keyDown(with: escapeKey())
        check(!editor.isDirty && !editor.document.isDirty,
              "a cancelled paste does not leave the picture marked edited",
              "still dirty")

        // 8. Transparency survives the trip through the clipboard.
        put(halfTransparentImage())
        editor.document.isDirty = false
        editor.isDirty = false
        editor.newFromClipboard(from: board)
        check(editor.document.hasAlpha,
              "an imported picture keeps its transparency", "hasAlpha false")
        let clear = editor.document.bitmap.pixel(x: 1, y: 1)
        check(clear.a == 0, "transparent pixels are still transparent, not white",
              "corner pixel \(clear)")

        // 9. A small paste leaves the canvas alone.
        reset(editor, width: 1024, height: 768)
        put(image(width: 200, height: 100, colour: .systemGreen))
        canvas.pasteFromClipboard(from: board)
        check(editor.canvasSize == CGSize(width: 1024, height: 768),
              "a paste that already fits does not resize the picture", "got \(editor.canvasSize)")

        // 10. A history of ordinary strokes costs tiles, not canvases.
        reset(editor, width: 2000, height: 1500)
        let doc = editor.document
        let canvasBytes = doc.width * doc.height * Bitmap.bytesPerPixel
        for step in 0..<32 {
            doc.checkpoint()
            doc.fillRegion(CGRect(x: step * 4, y: 0, width: 3, height: 3), with: .systemRed)
        }
        check(doc.history.depth == 32, "thirty-two strokes are thirty-two undo steps",
              "depth \(doc.history.depth)")
        // Whole-image snapshots would be 33 canvases here: 396 MB.
        check(doc.history.byteCount < canvasBytes * 2,
              "a history of small strokes stays near one canvas, not thirty-three",
              "\(doc.history.byteCount / 1_048_576) MB for a \(canvasBytes / 1_048_576) MB canvas")
        for _ in 0..<32 { editor.undo() }
        let unpainted = doc.bitmap.pixel(x: 1, y: doc.height - 2)
        check(unpainted.r > 200 && unpainted.g > 200 && unpainted.b > 200,
              "undoing all thirty-two of them puts every pixel back",
              "corner pixel \(unpainted)")

        // 11. The byte budget drops the oldest step rather than growing without end.
        reset(editor, width: 1200, height: 900)
        let budgeted = PaintDocument(width: 1200, height: 900)
        for _ in 0..<40 {
            budgeted.checkpoint()
            budgeted.apply(.invert)          // every pixel differs: no tile can be shared
        }
        check(budgeted.history.byteCount <= budgeted.history.byteBudget,
              "whole-canvas steps stay inside the undo memory budget",
              "\(budgeted.history.byteCount / 1_048_576) MB over a budget of \(budgeted.history.byteBudget / 1_048_576) MB")
        check(budgeted.history.canUndo, "and the history keeps at least one step", "no undo left")

        FileHandle.standardError.write(Data("selftest: \(failures == 0 ? "all checks passed" : "\(failures) failed")\n".utf8))
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    /// Back to a clean, undirtied document without the unsaved-work alert a headless run
    /// could never answer.
    private static func reset(_ editor: Editor, width: Int, height: Int) {
        editor.canvas?.deselect()
        editor.document.isDirty = false
        editor.isDirty = false
        editor.newDocument(width: width, height: height)
        editor.document.isDirty = false
        editor.isDirty = false
    }

    private static func image(width: Int, height: Int, colour: NSColor) -> CGImage {
        let bitmap = Bitmap(width: width, height: height, fill: colour.cgColor)
        return bitmap.makeImage()!
    }

    /// Left half solid, right half empty — the shape of a window screenshot's corners.
    private static func halfTransparentImage() -> CGImage {
        let bitmap = Bitmap(width: 40, height: 40)
        bitmap.context.setFillColor(NSColor.systemRed.cgColor)
        bitmap.context.fill(CGRect(x: 20, y: 0, width: 20, height: 40))
        return bitmap.makeImage()!
    }

    private static func put(_ image: CGImage) {
        ImageFile.writeToPasteboard(image, to: board)
    }

    private static func escapeKey() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "\u{1b}",
                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    private static func check(_ passed: Bool, _ what: String, _ detail: @autoclosure () -> String) {
        if passed {
            note("ok    \(what)")
        } else {
            failures += 1
            note("FAIL  \(what) — \(detail())")
        }
    }

    private static func note(_ message: String) {
        FileHandle.standardError.write(Data("selftest: \(message)\n".utf8))
    }
}
