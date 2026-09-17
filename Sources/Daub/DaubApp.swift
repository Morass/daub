import AppKit
import SwiftUI

@main
struct DaubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var editor = Editor()

    var body: some Scene {
        Window("Daub", id: "canvas") {
            ContentView(editor: editor)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { DaubCommands(editor: editor) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window must not quit. With terminate-on-close, ⌘W ran the unsaved-work
    /// alert *after* the window was already gone, so pressing Cancel left an app running
    /// with no canvas and no way back to the drawing. Closing now just hides it; the
    /// drawing stays in memory and clicking the Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// Quitting is the commonest way to lose a drawing, and the one path that had no
    /// prompt: New and Open asked, ⌘Q did not.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editor = Editor.current else { return .terminateNow }
        return editor.confirmDiscardIfNeeded() ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DaubCommands: Commands {
    @ObservedObject var editor: Editor

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { editor.newDocument() }.keyboardShortcut("n")
            Button("Open…") { editor.open() }.keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { _ = editor.save() }.keyboardShortcut("s")
            Button("Save As…") { _ = editor.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { editor.undo() }
                .keyboardShortcut("z").disabled(!editor.canUndo)
            Button("Redo") { editor.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!editor.canRedo)
        }

        // Cut/Copy/Paste/Select All stay as the standard responder-chain items so they
        // work inside the text tool and the sheets; only Deselect is ours to add.
        CommandGroup(after: .pasteboard) {
            Button("Deselect") { editor.deselect() }.keyboardShortcut("d")
        }

        CommandMenu("Image") {
            Button("Canvas Size…") {
                NotificationCenter.default.post(name: .daubShowResizeSheet, object: nil)
            }
            .keyboardShortcut("r")
            Divider()
            Button("Flip Horizontal") { editor.apply(.flipHorizontal) }
            Button("Flip Vertical") { editor.apply(.flipVertical) }
            Button("Rotate Left") { editor.apply(.rotateLeft) }
            Button("Rotate Right") { editor.apply(.rotateRight) }
            Divider()
            Button("Invert Colours") { editor.apply(.invert) }.keyboardShortcut("i")
            Button("Clear Image") { editor.clearCanvas() }
                .keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandMenu("Tools") {
            // Titles carry the bare-key hint; the canvas handles the keystroke itself so
            // the text tool can still be typed into.
            ForEach(Tool.allCases) { tool in
                Button("\(tool.title)   \(String(tool.shortcut.character).uppercased())") {
                    editor.tool = tool
                }
            }
            Divider()
            Button("Swap Colours   X") { editor.swapColours() }
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") { editor.zoomIn() }.keyboardShortcut("+")
            Button("Zoom Out") { editor.zoomOut() }.keyboardShortcut("-")
            Button("Actual Size") { editor.actualSize() }.keyboardShortcut("1")
            Button("Fit in Window") { editor.zoomToFit() }.keyboardShortcut("0")
            Divider()
            Toggle("Show Pixel Grid", isOn: $editor.showGrid)
        }
    }
}
