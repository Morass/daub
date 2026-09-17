import CoreGraphics

public enum ShapeKind: String, CaseIterable, Sendable {
    case line, rectangle, roundedRectangle, ellipse
}

/// Outline / fill behaviour of the shape tools, as in the classic three-way selector.
public enum ShapeFill: String, CaseIterable, Sendable {
    case outline, filled, filledOutline
}

public enum Shapes {
    /// Draw a shape into any context — the live preview overlay and the committed bitmap
    /// share this one routine, so what you drag is exactly what lands.
    public static func draw(_ kind: ShapeKind, in ctx: CGContext, from start: CGPoint, to end: CGPoint,
                            stroke: CGColor, fill: CGColor, style: ShapeFill,
                            lineWidth: CGFloat, antialias: Bool, cornerRadius: CGFloat = 12) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(antialias)
        ctx.setLineWidth(max(1, lineWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(stroke)
        ctx.setFillColor(fill)

        if kind == .line {
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            return
        }

        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        let path: CGPath
        switch kind {
        case .rectangle:
            path = CGPath(rect: rect, transform: nil)
        case .roundedRectangle:
            let r = min(cornerRadius, min(rect.width, rect.height) / 2)
            path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .ellipse:
            path = CGPath(ellipseIn: rect, transform: nil)
        case .line:
            return
        }

        if style != .outline {
            ctx.addPath(path)
            ctx.fillPath()
        }
        if style != .filled {
            ctx.addPath(path)
            ctx.strokePath()
        }
    }
}
