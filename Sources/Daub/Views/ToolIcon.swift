import SwiftUI

/// Toolbox glyph: SF Symbol where one reads cleanly, hand-drawn vector where it doesn't.
///
/// The shape tools and the airbrush draw their own glyph — a real rectangle beats any symbol that merely
/// suggests one, and it stays crisp at every size without shipping a single asset.
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 15
    /// Selected tools sit on a solid accent tile, where a coloured glyph would muddy;
    /// there the icon goes plain white instead.
    var coloured: Bool = true

    var body: some View {
        Group {
            if let symbol = tool.symbol, ToolIcon.symbolExists(symbol) {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .regular))
            } else {
                ShapeGlyph(tool: tool)
                    .frame(width: size + 3, height: size + 3)
            }
        }
        .foregroundStyle(coloured ? tool.tint : Color.white)
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
                case .gradient:
                    path.addRect(r)
                case .airbrush:
                    // A spray can, its nozzle pointing right, and a fan of dots leaving it.
                    let w = r.width, h = r.height
                    let body = CGRect(x: r.minX, y: r.minY + h * 0.36, width: w * 0.44, height: h * 0.64)
                    path.addRoundedRect(in: body, cornerSize: CGSize(width: 2, height: 2))
                    let cap = CGRect(x: body.minX + w * 0.1, y: r.minY + h * 0.16,
                                     width: w * 0.24, height: h * 0.2)
                    path.addRect(cap)
                    path.move(to: CGPoint(x: cap.maxX, y: cap.midY))
                    path.addLine(to: CGPoint(x: cap.maxX + w * 0.1, y: cap.midY))
                    for (dx, dy) in [(0.74, 0.02), (0.98, 0.02), (0.86, 0.26), (0.98, 0.5), (0.74, 0.5)] {
                        let c = CGPoint(x: r.minX + w * dx, y: r.minY + h * dy)
                        path.addEllipse(in: CGRect(x: c.x - 0.4, y: c.y - 0.4, width: 0.8, height: 0.8))
                    }
                default:
                    path.addEllipse(in: r.insetBy(dx: r.width / 3, dy: r.height / 3))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .overlay(
                // The gradient tool shows what it does: a swatch fading out inside its box.
                tool == .gradient
                    ? AnyView(LinearGradient(colors: [tool.tint, tool.tint.opacity(0.05)],
                                             startPoint: .leading, endPoint: .trailing)
                        .mask(Path { $0.addRect(CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)) }))
                    : AnyView(EmptyView())
            )
        }
    }
}
