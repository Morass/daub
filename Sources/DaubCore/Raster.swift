import CoreGraphics
import Foundation

/// Pixel-exact drawing, bypassing CoreGraphics.
///
/// The pencil and eraser must land on whole pixels with no anti-aliasing — a 1px CG stroke
/// at integer coordinates straddles two pixel rows and comes out grey. Bresenham does not.
public enum Raster {
    /// Square nib centred on (x, y), the classic pencil/eraser footprint.
    public static func stamp(_ bitmap: Bitmap, x: Int, y: Int, size: Int, color: RGBA) {
        let s = max(1, size)
        let half = (s - 1) / 2
        for dy in 0..<s {
            for dx in 0..<s {
                bitmap.setPixel(x: x - half + dx, y: y - half + dy, to: color)
            }
        }
    }

    @discardableResult
    public static func line(_ bitmap: Bitmap, from a: (x: Int, y: Int), to b: (x: Int, y: Int),
                            size: Int, color: RGBA) -> CGRect {
        var x0 = a.x, y0 = a.y
        let x1 = b.x, y1 = b.y
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            stamp(bitmap, x: x0, y: y0, size: size, color: color)
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        let pad = CGFloat(max(1, size))
        return CGRect(x: CGFloat(min(a.x, b.x)), y: CGFloat(min(a.y, b.y)),
                      width: CGFloat(abs(b.x - a.x)), height: CGFloat(abs(b.y - a.y)))
            .insetBy(dx: -pad, dy: -pad)
    }

    /// One airbrush puff: `density` random pixels inside `radius`, Gaussian-ish toward the centre.
    @discardableResult
    public static func spray(_ bitmap: Bitmap, x: Int, y: Int, radius: Int, density: Int,
                             color: RGBA, using generator: inout some RandomNumberGenerator) -> CGRect {
        let r = max(1, radius)
        for _ in 0..<max(1, density) {
            let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
            let dist = Double(r) * sqrt(Double.random(in: 0...1, using: &generator))
            let px = x + Int((cos(angle) * dist).rounded())
            let py = y + Int((sin(angle) * dist).rounded())
            bitmap.setPixel(x: px, y: py, to: color)
        }
        return CGRect(x: x - r - 1, y: y - r - 1, width: 2 * r + 2, height: 2 * r + 2)
    }
}
