import CoreGraphics

/// Where pasted content goes and how big the canvas has to be to hold it.
///
/// Pure geometry, so the rules can be pinned by tests without a window, a pasteboard or a
/// running app.
public enum CanvasFit {
    /// True when `content` pasted at the canvas's top-left corner lands entirely inside it.
    public static func fits(_ content: CGSize, in canvas: CGSize) -> Bool {
        content.width <= canvas.width && content.height <= canvas.height
    }

    /// The canvas size needed to hold `content` pasted at the top-left corner: unchanged
    /// where it already fits, grown on the axes where it does not.
    ///
    /// Growing is per-axis and one-way — a paste never shrinks the picture, and a wide,
    /// short clipboard image does not lop the bottom off a tall canvas. Content that no
    /// allocatable canvas could hold leaves the canvas exactly as it is, because growing
    /// to the maximum would still clip the paste while costing the user a canvas they
    /// never asked for.
    public static func grown(canvas: CGSize, toFit content: CGSize) -> CGSize {
        let width = max(pixels(canvas.width), pixels(content.width))
        let height = max(pixels(canvas.height), pixels(content.height))
        guard width <= Bitmap.maxDimension, height <= Bitmap.maxDimension,
              width * height <= Bitmap.maxPixels
        else { return canvas }
        return CGSize(width: width, height: height)
    }

    /// Pixel count from a size, clamped on the way in: one past the dimension limit still
    /// reads as "too big" above, and no CGFloat — however nonsensical — can trap the
    /// conversion to Int.
    private static func pixels(_ value: CGFloat) -> Int {
        guard value.isFinite, value > 0 else { return 1 }
        // Clamp as a CGFloat, before the conversion: `Int(1e30)` traps outright.
        return Int(min(value.rounded(), CGFloat(Bitmap.maxDimension + 1)))
    }
}
