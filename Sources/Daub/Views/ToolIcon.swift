import SwiftUI

/// Toolbox glyph: SF Symbol where one reads cleanly, hand-drawn vector where it doesn't.
///
/// The shape tools draw their own glyph — a real rectangle beats any symbol that merely
/// suggests one, and it stays crisp at every size without shipping a single asset.
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 15

    var body: some View {
        if let symbol = tool.symbol, ToolIcon.symbolExists(symbol) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
        } else {
            ShapeGlyph(tool: tool)
                .frame(width: size + 3, height: size + 3)
        }
    }

    /// SF Symbol availability shifts between macOS releases; a missing name renders as a
    /// blank button, so fall back rather than trust the catalogue.
    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

private struct ShapeGlyph: View {
    let tool: Tool

    var body: some View {
        GeometryReader { geo in
            let r = CGRect(origin: .zero, size: geo.size).insetBy(dx: 1.5, dy: 1.5)
            Path { path in
                switch tool {
                case .line:
                    path.move(to: CGPoint(x: r.minX, y: r.maxY))
                    path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                case .rectangle:
                    path.addRect(r)
                case .roundedRectangle:
                    path.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))
                case .ellipse:
                    path.addEllipse(in: r)
                default:
                    path.addEllipse(in: r.insetBy(dx: r.width / 3, dy: r.height / 3))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
