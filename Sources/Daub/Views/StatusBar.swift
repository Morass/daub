import SwiftUI

struct StatusBar: View {
    @ObservedObject var editor: Editor
    @ObservedObject var readout: CursorReadout

    var body: some View {
        HStack(spacing: 16) {
            field(icon: "scope",
                  text: readout.pixel.map { "\(Int($0.x)), \(Int($0.y))" } ?? "—")
                .frame(width: 96, alignment: .leading)

            field(icon: "aspectratio",
                  text: "\(Int(editor.canvasSize.width)) × \(Int(editor.canvasSize.height))")

            if let selection = readout.selection {
                field(icon: "rectangle.dashed",
                      text: "\(Int(selection.width)) × \(Int(selection.height))")
            }

            Spacer()

            Button { editor.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless)
            Menu("\(Int(editor.zoom * 100))%") {
                ForEach(Editor.zoomSteps, id: \.self) { step in
                    Button("\(Int(step * 100))%") { editor.zoom = step }
                }
                Divider()
                Button("Fit in Window") { editor.zoomToFit() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 72)
            Button { editor.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func field(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text)
        }
    }
}
