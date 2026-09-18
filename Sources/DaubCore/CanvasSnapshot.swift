import CoreGraphics
import Foundation

/// One square of canvas pixels, held by *reference* so that two snapshots can share every
/// square the step between them did not touch.
///
/// That sharing is the whole point. A full-canvas undo snapshot of a 6000x4000 picture is
/// 96 MB, and thirty-two of them are three gigabytes — for a history whose steps are
/// almost always a pencil line or a small fill. Tiled, a stroke costs the handful of tiles
/// it actually crossed and the rest of the canvas is the same objects the previous
/// snapshot already holds.
public final class Tile {
    @usableFromInline let bytes: ContiguousArray<UInt8>

    public var byteCount: Int { bytes.count }

    init(_ bytes: ContiguousArray<UInt8>) { self.bytes = bytes }

    /// True when this tile already holds exactly the bytes now in the canvas, so the new
    /// snapshot can point at this object instead of allocating a copy of them.
    func matches(base: UnsafeMutablePointer<UInt8>, x0: Int, y0: Int,
                 rowBytes: Int, lineBytes: Int, lines: Int) -> Bool {
        guard bytes.count == lineBytes * lines else { return false }
        return bytes.withUnsafeBytes { src in
            guard let source = src.baseAddress else { return false }
            for line in 0..<lines {
                let there = UnsafeRawPointer(base + (y0 + line) * rowBytes + x0 * Bitmap.bytesPerPixel)
                if memcmp(source + line * lineBytes, there, lineBytes) != 0 { return false }
            }
            return true
        }
    }

    func write(into base: UnsafeMutablePointer<UInt8>, x0: Int, y0: Int,
               rowBytes: Int, lineBytes: Int, lines: Int) {
        guard bytes.count == lineBytes * lines else { return }
        bytes.withUnsafeBytes { src in
            guard let source = src.baseAddress else { return }
            for line in 0..<lines {
                memcpy(base + (y0 + line) * rowBytes + x0 * Bitmap.bytesPerPixel,
                       source + line * lineBytes, lineBytes)
            }
        }
    }
}

/// The whole canvas at one moment, as a grid of tiles. Cheap to copy: the tiles are shared,
/// not duplicated.
public struct CanvasSnapshot {
    public let width: Int
    public let height: Int
    public let tileSize: Int
    public let columns: Int
    public let rows: Int
    var tiles: [Tile]

    /// What this snapshot would cost on its own, ignoring the tiles it shares with others.
    /// `UndoHistory.byteCount` is the number that matters; this one is for tests and docs.
    public var byteCount: Int { tiles.reduce(0) { $0 + $1.byteCount } }
    public var tileCount: Int { tiles.count }

    /// How many tiles this snapshot points at the *same* objects as `other` — i.e. how much
    /// of the picture the step between them left alone.
    public func sharedTileCount(with other: CanvasSnapshot) -> Int {
        guard columns == other.columns, rows == other.rows else { return 0 }
        var shared = 0
        for index in tiles.indices where tiles[index] === other.tiles[index] { shared += 1 }
        return shared
    }
}

public extension Bitmap {
    /// 128 x 128 pixels, 64 KB a tile: small enough that a pencil stroke keeps a couple of
    /// them and large enough that a full canvas is a few hundred objects rather than
    /// hundreds of thousands.
    static let snapshotTileSize = 128

    /// Copy the canvas into a tiled snapshot, reusing every tile of `previous` that still
    /// holds the same pixels.
    ///
    /// The comparison is a `memcmp` per tile row against live memory — it allocates nothing
    /// for an unchanged tile, and reading the canvas once is what the old `makeImage()`
    /// snapshot did anyway.
    func snapshot(tileSize: Int = Bitmap.snapshotTileSize,
                  reusing previous: CanvasSnapshot? = nil) -> CanvasSnapshot {
        let side = max(1, tileSize)
        let columns = (width + side - 1) / side
        let rows = (height + side - 1) / side
        let reusable: CanvasSnapshot? = {
            guard let previous, previous.width == width, previous.height == height,
                  previous.tileSize == side else { return nil }
            return previous
        }()
        var tiles: [Tile] = []
        tiles.reserveCapacity(columns * rows)
        withRawPixels { base, w, h, rowBytes in
            for row in 0..<rows {
                let y0 = row * side
                let lines = min(side, h - y0)
                for column in 0..<columns {
                    let x0 = column * side
                    let lineBytes = min(side, w - x0) * Bitmap.bytesPerPixel
                    if let old = reusable?.tiles[row * columns + column],
                       old.matches(base: base, x0: x0, y0: y0, rowBytes: rowBytes,
                                   lineBytes: lineBytes, lines: lines) {
                        tiles.append(old)
                        continue
                    }
                    var bytes = ContiguousArray<UInt8>(repeating: 0, count: lineBytes * lines)
                    bytes.withUnsafeMutableBytes { dst in
                        guard let destination = dst.baseAddress else { return }
                        for line in 0..<lines {
                            memcpy(destination + line * lineBytes,
                                   base + (y0 + line) * rowBytes + x0 * Bitmap.bytesPerPixel,
                                   lineBytes)
                        }
                    }
                    tiles.append(Tile(bytes))
                }
            }
        }
        return CanvasSnapshot(width: width, height: height, tileSize: side,
                              columns: columns, rows: rows, tiles: tiles)
    }

    /// Put a snapshot back. The canvas must already be the snapshot's size — restoring one
    /// taken before a resize means building a bitmap of that size first.
    @discardableResult
    func restore(_ snapshot: CanvasSnapshot) -> Bool {
        guard snapshot.width == width, snapshot.height == height else { return false }
        let side = snapshot.tileSize
        withRawPixels { base, w, h, rowBytes in
            for row in 0..<snapshot.rows {
                let y0 = row * side
                let lines = min(side, h - y0)
                for column in 0..<snapshot.columns {
                    let x0 = column * side
                    let lineBytes = min(side, w - x0) * Bitmap.bytesPerPixel
                    snapshot.tiles[row * snapshot.columns + column]
                        .write(into: base, x0: x0, y0: y0, rowBytes: rowBytes,
                               lineBytes: lineBytes, lines: lines)
                }
            }
        }
        return true
    }
}
