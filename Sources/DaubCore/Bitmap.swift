import CoreGraphics
import Foundation

/// A straight RGBA8 (sRGB, premultiplied-last) pixel buffer with a CGContext over it.
///
/// The canvas is always fully opaque, like classic Paint: erasing means painting the
/// background colour, not punching a hole. That keeps every blend cheap and every
/// saved PNG free of surprise transparency.
public final class Bitmap {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var context: CGContext
    private var storage: UnsafeMutableRawPointer
    private var cachedLiveImage: CGImage?

    public static let bytesPerPixel = 4

    public var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    public var bytesPerRow: Int { width * Bitmap.bytesPerPixel }

    /// Largest canvas Daub will allocate: 268 MB of pixels. Past this the honest answer
    /// is an error, not a 1.5 GB allocation or an overflowed `width * height * 4`.
    public static let maxPixels = 67_108_864          // e.g. 8192 x 8192
    public static let maxDimension = 32_768

    public struct TooLarge: Error, CustomStringConvertible {
        public let width: Int, height: Int
        public var description: String {
            "\(width) x \(height) is larger than Daub can open (limit \(Bitmap.maxDimension) per side, \(Bitmap.maxPixels) pixels)."
        }
    }

    /// Throwing counterpart of `init`, for sizes that come from a file rather than from us.
    public static func checked(width: Int, height: Int, fill: CGColor? = nil) throws -> Bitmap {
        guard width > 0, height > 0,
              width <= maxDimension, height <= maxDimension,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= maxPixels
        else { throw TooLarge(width: width, height: height) }
        return Bitmap(width: width, height: height, fill: fill)
    }

    public init(width: Int, height: Int, fill: CGColor? = nil) {
        let w = min(max(1, width), Bitmap.maxDimension)
        let h = min(max(1, height), Bitmap.maxDimension)
        let rowBytes = w * Bitmap.bytesPerPixel
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * h, alignment: 16)
        buffer.initializeMemory(as: UInt8.self, repeating: 255, count: rowBytes * h)
        guard let ctx = CGContext(
            data: buffer,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Daub: could not create a \(w)x\(h) bitmap context")
        }
        self.width = w
        self.height = h
        self.storage = buffer
        self.context = ctx
        if let fill {
            ctx.setFillColor(fill)
            ctx.fill(bounds)
        }
    }

    deinit { storage.deallocate() }

    /// A true copy of the pixels — for undo snapshots and for saving.
    public func makeImage() -> CGImage? { context.makeImage() }

    /// A CGImage that *reads through* to this bitmap's buffer instead of copying it.
    ///
    /// `makeImage()` memcpys the whole canvas; calling it once per frame costs 48 MB a
    /// frame at 4000x3000, which is what the on-screen redraw was doing. The provider
    /// here is created once per buffer and re-read by CoreGraphics at draw time, so a
    /// redraw costs only the pixels it actually blits. Never hand this to anything that
    /// outlives the next mutation — it is a window onto live memory, not a snapshot.
    public var liveImage: CGImage? {
        if let cached = cachedLiveImage { return cached }
        let byteCount = bytesPerRow * height
        guard let provider = CGDataProvider(dataInfo: nil, data: storage, size: byteCount,
                                            releaseData: { _, _, _ in })
        else { return nil }
        let image = CGImage(width: width, height: height,
                            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)
        cachedLiveImage = image
        return image
    }

    /// `liveImage` cropped to a region, in drawing coordinates. Same caveat: a window
    /// onto live memory, valid only until the next mutation.
    public func croppedLiveImage(in rect: CGRect) -> CGImage? {
        guard let full = liveImage else { return nil }
        let r = rect.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1 else { return nil }
        return full.cropping(to: CGRect(x: r.minX, y: CGFloat(height) - r.maxY,
                                        width: r.width, height: r.height))
    }

    /// Crop in *drawing* coordinates. `CGImage.cropping` works in the image's own
    /// top-down space, so a selection near the bottom of the canvas would otherwise
    /// come back as a copy of the top.
    public func croppedImage(in rect: CGRect) -> CGImage? {
        guard let full = makeImage() else { return nil }
        let r = rect.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1 else { return nil }
        let topDown = CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height)
        return full.cropping(to: topDown)
    }

    /// Overwrite every pixel with `image`, scaled to fit the current size.
    public func replace(with image: CGImage) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
        context.restoreGState()
    }

    /// Classic-Paint canvas resize: content keeps its top-left corner, new area is `fill`.
    public func resized(to newWidth: Int, _ newHeight: Int, fill: CGColor) -> Bitmap {
        let out = Bitmap(width: newWidth, height: newHeight, fill: fill)
        guard let image = makeImage() else { return out }
        // CoreGraphics is bottom-left origin, so anchoring top-left means offsetting in y.
        let dy = CGFloat(out.height - height)
        out.context.saveGState()
        out.context.setBlendMode(.copy)
        out.context.interpolationQuality = .none
        out.context.draw(image, in: CGRect(x: 0, y: dy, width: CGFloat(width), height: CGFloat(height)))
        out.context.restoreGState()
        return out
    }

    // MARK: - Pixel access

    // A CGBitmapContext stores row 0 of its buffer as the *top* row of the picture, while
    // its drawing coordinates put the origin at the bottom left. Every accessor here works
    // in drawing coordinates and flips on the way to memory, so the raster tools (pencil,
    // fill) and the CoreGraphics tools (brush, shapes, text) share one coordinate space.
    // Getting this wrong mirrors half the toolbox against the other half.

    @inline(__always)
    private func offset(x: Int, y: Int) -> Int {
        (height - 1 - y) * bytesPerRow + x * Bitmap.bytesPerPixel
    }

    public func pixel(x: Int, y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        let p = storage.assumingMemoryBound(to: UInt8.self) + offset(x: x, y: y)
        return RGBA(r: p[0], g: p[1], b: p[2], a: p[3])
    }

    public func setPixel(x: Int, y: Int, to c: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let p = storage.assumingMemoryBound(to: UInt8.self) + offset(x: x, y: y)
        p[0] = c.r; p[1] = c.g; p[2] = c.b; p[3] = c.a
    }

    /// Direct buffer access in drawing coordinates, for loops too hot for per-pixel calls.
    public func withPixelBuffer<T>(_ body: (PixelBuffer) -> T) -> T {
        body(PixelBuffer(base: storage.assumingMemoryBound(to: UInt8.self),
                         width: width, height: height, bytesPerRow: bytesPerRow))
    }

    /// Raw memory, in storage order. Only for operations that treat every pixel alike
    /// (inversion, histograms) and therefore cannot care which way up the rows run.
    public func withRawPixels<T>(_ body: (UnsafeMutablePointer<UInt8>, Int, Int, Int) -> T) -> T {
        body(storage.assumingMemoryBound(to: UInt8.self), width, height, bytesPerRow)
    }
}

public struct PixelBuffer {
    public let base: UnsafeMutablePointer<UInt8>
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    @inline(__always)
    private func offset(_ x: Int, _ y: Int) -> Int {
        (height - 1 - y) * bytesPerRow + x * 4
    }

    @inline(__always)
    public func get(_ x: Int, _ y: Int) -> RGBA {
        let p = base + offset(x, y)
        return RGBA(r: p[0], g: p[1], b: p[2], a: p[3])
    }

    @inline(__always)
    public func set(_ x: Int, _ y: Int, _ c: RGBA) {
        let p = base + offset(x, y)
        p[0] = c.r; p[1] = c.g; p[2] = c.b; p[3] = c.a
    }
}

public extension Bitmap {
    /// Rotate a quarter turn. `clockwise` is what the user sees: CoreGraphics rotates
    /// counter-clockwise for a positive angle in its y-up space, so the sign here is the
    /// opposite of the one that looks right in the source.
    func rotatedQuarterTurn(clockwise: Bool, fill: CGColor) -> Bitmap {
        let out = Bitmap(width: height, height: width, fill: fill)
        guard let image = makeImage() else { return out }
        let ctx = out.context
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        if clockwise {
            ctx.translateBy(x: 0, y: CGFloat(out.height))
            ctx.rotate(by: -.pi / 2)
        } else {
            ctx.translateBy(x: CGFloat(out.width), y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        ctx.restoreGState()
        return out
    }

    func flip(horizontally: Bool) {
        guard let image = makeImage() else { return }
        context.saveGState()
        context.setBlendMode(.copy)
        if horizontally {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: bounds)
        context.restoreGState()
    }

    func invertColours() {
        withRawPixels { base, w, h, rowBytes in
            for y in 0..<h {
                let row = base + y * rowBytes
                for x in 0..<w {
                    let p = row + x * 4
                    p[0] = 255 &- p[0]; p[1] = 255 &- p[1]; p[2] = 255 &- p[2]
                }
            }
        }
    }
}

public struct RGBA: Equatable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init?(_ color: CGColor) {
        guard let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         intent: .defaultIntent, options: nil),
              let c = srgb.components, c.count >= 3 else { return nil }
        func b(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        let alpha = srgb.numberOfComponents >= 4 ? c[3] : 1
        self.init(r: b(c[0]), g: b(c[1]), b: b(c[2]), a: b(alpha))
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    /// Per-channel distance, the comparison a fill tolerance slider needs.
    @inlinable
    public func matches(_ other: RGBA, tolerance: Int) -> Bool {
        if tolerance == 0 { return self == other }
        return abs(Int(r) - Int(other.r)) <= tolerance
            && abs(Int(g) - Int(other.g)) <= tolerance
            && abs(Int(b) - Int(other.b)) <= tolerance
            && abs(Int(a) - Int(other.a)) <= tolerance
    }
}
