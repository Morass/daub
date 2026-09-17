import CoreGraphics

/// Scanline flood fill with an explicit visited set.
///
/// The visited set is what makes a tolerance slider safe: when the replacement colour is
/// itself within tolerance of the seed colour, a naive fill re-enters spans forever.
public enum FloodFill {
    /// - Returns: the dirty rect in bitmap coordinates, or nil when nothing changed.
    @discardableResult
    public static func fill(_ bitmap: Bitmap, x: Int, y: Int,
                            with color: RGBA, tolerance: Int = 0) -> CGRect? {
        let w = bitmap.width, h = bitmap.height
        guard x >= 0, y >= 0, x < w, y < h else { return nil }
        let seed = bitmap.pixel(x: x, y: y)
        if seed == color && tolerance == 0 { return nil }

        var visited = [Bool](repeating: false, count: w * h)
        var stack: [(Int, Int)] = [(x, y)]
        var minX = x, maxX = x, minY = y, maxY = y
        var touched = false

        bitmap.withPixelBuffer { buffer in
            let width = buffer.width
            @inline(__always) func at(_ px: Int, _ py: Int) -> RGBA { buffer.get(px, py) }
            @inline(__always) func put(_ px: Int, _ py: Int) { buffer.set(px, py, color) }

            while let (sx, sy) = stack.popLast() {
                var left = sx
                while left >= 0, !visited[sy * width + left], at(left, sy).matches(seed, tolerance: tolerance) {
                    left -= 1
                }
                left += 1
                var right = sx
                while right < width, !visited[sy * width + right], at(right, sy).matches(seed, tolerance: tolerance) {
                    right += 1
                }
                right -= 1
                guard left <= right else { continue }

                for px in left...right {
                    visited[sy * width + px] = true
                    put(px, sy)
                }
                touched = true
                minX = min(minX, left); maxX = max(maxX, right)
                minY = min(minY, sy); maxY = max(maxY, sy)

                for ny in [sy - 1, sy + 1] where ny >= 0 && ny < h {
                    var px = left
                    while px <= right {
                        if !visited[ny * width + px], at(px, ny).matches(seed, tolerance: tolerance) {
                            stack.append((px, ny))
                            // Skip the rest of this run; the span scan will claim it.
                            while px <= right, at(px, ny).matches(seed, tolerance: tolerance) { px += 1 }
                        }
                        px += 1
                    }
                }
            }
        }

        guard touched else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
