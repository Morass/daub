import AppKit
import DaubCore

/// End-to-end checks that drive the real app through the real clipboard, because the
/// paste path lives in the app target where `swift test` cannot reach it.
///
///     DAUB_SELFTEST=clipboard build/Daub.app/Contents/MacOS/Daub
///
/// Prints one line per check and exits non-zero on the first failure. `make selftest`
/// wraps it. It uses the general pasteboard, so it does clear whatever was on it.
@MainActor
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["DAUB_SELFTEST"] == "clipboard" else { return }
        // One hop through the run loop so SwiftUI has built the chrome and the canvas view
        // exists — the paste path goes through it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run() }
    }

    private static var failures = 0

    private static func run() {
        guard let editor = Editor.current, let canvas = editor.canvas else {
            note("FAIL  no editor or canvas")
            exit(1)
        }

        // 1. A whole picture imported from the clipboard sizes the canvas to it.
        put(image(width: 2400, height: 1600, colour: .systemBlue))
        editor.newFromClipboard()
        check(editor.canvasSize == CGSize(width: 2400, height: 1600),
              "New from Clipboard sizes the canvas to the clipboard image",
              "got \(editor.canvasSize)")
        check(editor.zoom < 1, "a picture larger than the window is zoomed to fit",
              "zoom \(editor.zoom)")
        check(editor.isDirty, "imported pixels count as unsaved work", "not dirty")

        // 2. Pasting into a smaller canvas grows the canvas instead of clipping.
        reset(editor, width: 1024, height: 768)
        put(image(width: 2000, height: 1500, colour: .systemRed))
        canvas.pasteFromClipboard()
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

        // 4. A small paste leaves the canvas alone.
        reset(editor, width: 1024, height: 768)
        put(image(width: 200, height: 100, colour: .systemGreen))
        canvas.pasteFromClipboard()
        check(editor.canvasSize == CGSize(width: 1024, height: 768),
              "a paste that already fits does not resize the picture", "got \(editor.canvasSize)")

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

    private static func put(_ image: CGImage) {
        ImageFile.writeToPasteboard(image)
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
