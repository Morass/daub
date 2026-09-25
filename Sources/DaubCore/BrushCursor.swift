import CoreGraphics

/// How big the on-screen outline of a tool's tip is, so the cursor shows the width the
/// stroke will actually have.
///
/// Pure geometry: the app turns the answer into an `NSCursor`, the rules live here where
/// tests can pin them.
public enum BrushCursor {
    /// The shape a tool leaves on the canvas.
    public enum Tip: Equatable, Sendable {
        /// Round tips: brush, clone stamp, line and shape outlines.
        case circle
        /// The pencil and eraser stamp whole pixels in a square.
        case square
        /// The airbrush: a round area the dots land in, not a solid tip.
        case spray
    }

    /// Below this the outline is too small to read, so the caller shows a crosshair.
    public static let smallest: CGFloat = 6
    /// Above this the system will not draw the cursor reliably, so the caller shows a
    /// crosshair rather than an outline smaller than the truth.
    public static let largest: CGFloat = 256

    /// Canvas pixels across the tip for a tool's size setting. The airbrush setting is a
    /// radius; every other size is already a width.
    public static func canvasDiameter(tip: Tip, size: Double) -> CGFloat {
        guard size.isFinite, size > 0 else { return 1 }
        switch tip {
        case .circle: return CGFloat(size)
        case .square: return CGFloat(max(1, Int(size)))      // the pencil stamps whole pixels
        case .spray: return CGFloat(2 * max(1, Int(size)) + 1)
        }
    }

    /// Points across the outline at `zoom`, or nil when a crosshair serves better: an
    /// outline too small to see, or too big for the system to draw as a cursor.
    public static func viewDiameter(tip: Tip, size: Double, zoom: CGFloat) -> CGFloat? {
        guard zoom.isFinite, zoom > 0 else { return nil }
        let d = canvasDiameter(tip: tip, size: size) * zoom
        guard d >= smallest, d <= largest else { return nil }
        return d
    }
}
