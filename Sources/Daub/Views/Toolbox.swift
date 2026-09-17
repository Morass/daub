import DaubCore
import SwiftUI

struct Toolbox: View {
    @ObservedObject var editor: Editor

    private let columns = [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Tool.allCases) { tool in
                        ToolButton(tool: tool, isSelected: editor.tool == tool) {
                            editor.tool = tool
                        }
                    }
                }

                Divider()
                options
            }
            .padding(12)
        }
        .frame(width: 186)
        .background(.bar)
    }

    @ViewBuilder
    private var options: some View {
        SectionLabel("Options")

        switch editor.tool.sizeKnob {
        case .pencil:
            LabelledSlider(title: "Size", value: $editor.pencilSize, range: 1...16, unit: "px")
        case .stroke:
            LabelledSlider(title: "Width", value: $editor.strokeWidth, range: 1...48, unit: "px")
        case .eraser:
            LabelledSlider(title: "Size", value: $editor.eraserSize, range: 1...96, unit: "px")
        case .spray:
            LabelledSlider(title: "Radius", value: $editor.sprayRadius, range: 2...80, unit: "px")
            LabelledSlider(title: "Flow", value: $editor.sprayDensity, range: 1...80, unit: "")
        case .none:
            EmptyView()
        }

        if editor.tool.isShape {
            Picker("", selection: $editor.shapeStyle) {
                Image(systemName: "square").tag(ShapeFill.outline)
                Image(systemName: "square.fill").tag(ShapeFill.filled)
                Image(systemName: "square.inset.filled").tag(ShapeFill.filledOutline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Outline · Filled · Filled with outline")
        }

        if editor.tool == .fill {
            LabelledSlider(title: "Tolerance", value: $editor.tolerance, range: 0...128, unit: "")
        }

        if editor.tool == .text {
            LabelledSlider(title: "Size", value: $editor.fontSize, range: 8...144, unit: "pt")
            Picker("Font", selection: $editor.fontName) {
                ForEach(Toolbox.fonts, id: \.self) { Text($0).font(.caption) }
            }
            .labelsHidden()
            .controlSize(.small)
        }

        if editor.tool != .pencil && editor.tool != .eraser {
            Toggle("Smooth edges", isOn: $editor.antialias)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Anti-alias brush and shape edges. The pencil is always hard-edged.")
        }

        Divider()
        SectionLabel("Canvas")
        Toggle("Pixel grid", isOn: $editor.showGrid)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help("Shown at 800% and above.")
    }

    private static let fonts = ["Helvetica Neue", "Avenir Next", "Menlo", "Georgia",
                                "Times New Roman", "Courier New", "Chalkboard SE", "Impact"]
}

private struct ToolButton: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolIcon(tool: tool)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
        )
        .help("\(tool.title)  (\(String(describing: tool.shortcut.character).uppercased()))")
        .accessibilityLabel(tool.title)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}

struct LabelledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}
