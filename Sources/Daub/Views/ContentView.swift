import SwiftUI

struct ContentView: View {
    @ObservedObject var editor: Editor
    @State private var showResize = false

    var body: some View {
        HStack(spacing: 0) {
            Toolbox(editor: editor)
            Divider()
            VStack(spacing: 0) {
                CanvasHost(editor: editor)
                Divider()
                PaletteBar(editor: editor)
                Divider()
                StatusBar(editor: editor, readout: editor.readout)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .toolbar { toolbarItems }
        .navigationTitle(editor.windowTitle)
        .sheet(isPresented: $showResize) { ResizeSheet(editor: editor) }
        .onReceive(NotificationCenter.default.publisher(for: .daubShowResizeSheet)) { _ in
            showResize = true
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup {
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo)
                .help("Undo  (⌘Z)")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo)
                .help("Redo  (⇧⌘Z)")
        }
        ToolbarItemGroup {
            Button { showResize = true } label: { Image(systemName: "aspectratio") }
                .help("Canvas size…")
            Button { editor.zoomToFit() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Fit in window  (⌘0)")
        }
    }
}

extension Notification.Name {
    static let daubShowResizeSheet = Notification.Name("DaubShowResizeSheet")
}

struct ResizeSheet: View {
    @ObservedObject var editor: Editor
    @Environment(\.dismiss) private var dismiss

    @State private var width = 1024
    @State private var height = 768
    @State private var scaleContents = false
    @State private var lockAspect = true
    @State private var initialised = false

    private var aspect: Double {
        Double(editor.canvasSize.width) / Double(max(1, Int(editor.canvasSize.height)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Canvas Size").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Width").foregroundStyle(.secondary)
                    TextField("", value: $width, format: .number)
                        .frame(width: 88)
                        .onChange(of: width) { _, new in
                            if lockAspect && scaleContents { height = max(1, Int(Double(new) / aspect)) }
                        }
                    Text("px").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Height").foregroundStyle(.secondary)
                    TextField("", value: $height, format: .number)
                        .frame(width: 88)
                        .onChange(of: height) { _, new in
                            if lockAspect && scaleContents { width = max(1, Int(Double(new) * aspect)) }
                        }
                    Text("px").foregroundStyle(.secondary)
                }
            }

            Toggle("Scale the picture to fit", isOn: $scaleContents)
                .help("Off: the canvas is cropped or extended with the background colour, anchored top-left.")
            Toggle("Keep proportions", isOn: $lockAspect)
                .disabled(!scaleContents)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Resize") {
                    editor.resizeCanvas(width: max(1, width), height: max(1, height),
                                        scaleContents: scaleContents)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            guard !initialised else { return }
            width = Int(editor.canvasSize.width)
            height = Int(editor.canvasSize.height)
            initialised = true
        }
    }
}
