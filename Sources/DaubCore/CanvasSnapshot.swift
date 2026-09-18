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
/// not duplicated. Used for the steps a patch cannot express — the ones that change the
/// size of the canvas, where "the pixels under this rectangle" means nothing.
public struct CanvasSnapshot {
    public let grid: TileGrid
    var tiles: [Tile]

    public var width: Int { grid.width }
    public var height: Int { grid.height }
    public var tileSize: Int { grid.tileSize }
    public var columns: Int { grid.columns }
    public var rows: Int { grid.rows }

    /// What this snapshot would cost on its own, ignoring the tiles it shares with others.
    /// `UndoHistory.byteCount` is the number that matters; this one is for tests and docs.
    public var byteCount: Int { tiles.reduce(0) { $0 + $1.byteCount } }
    public var tileCount: Int { tiles.count }

    /// How many tiles this snapshot points at the *same* objects as `other` — i.e. how much
    /// of the picture the step between them left alone.
    public func sharedTileCount(with other: CanvasSnapshot) -> Int {
        guard grid == other.grid else { return 0 }
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
        let grid = TileGrid(width: width, height: height, tileSize: tileSize)
        let side = grid.tileSize
        let columns = grid.columns
        let rows = grid.rows
        let reusable: CanvasSnapshot? = {
            guard let previous, previous.grid == grid else { return nil }
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
        return CanvasSnapshot(grid: grid, tiles: tiles)
    }

    /// One tile's bytes, in storage order — the currency both the patches and the snapshots
    /// deal in.
    func tile(row: Int, column: Int, grid: TileGrid) -> Tile {
        let side = grid.tileSize
        let y0 = row * side
        let lines = min(side, height - y0)
        let x0 = column * side
        let lineBytes = min(side, width - x0) * Bitmap.bytesPerPixel
        var bytes = ContiguousArray<UInt8>(repeating: 0, count: lineBytes * lines)
        withRawPixels { base, _, _, rowBytes in
            bytes.withUnsafeMutableBytes { dst in
                guard let destination = dst.baseAddress else { return }
                for line in 0..<lines {
                    memcpy(destination + line * lineBytes,
                           base + (y0 + line) * rowBytes + x0 * Bitmap.bytesPerPixel, lineBytes)
                }
            }
        }
        return Tile(bytes)
    }

    func write(_ tile: Tile, row: Int, column: Int, grid: TileGrid) {
        let side = grid.tileSize
        let y0 = row * side
        let lines = min(side, height - y0)
        let x0 = column * side
        let lineBytes = min(side, width - x0) * Bitmap.bytesPerPixel
        withRawPixels { base, _, _, rowBytes in
            tile.write(into: base, x0: x0, y0: y0, rowBytes: rowBytes,
                       lineBytes: lineBytes, lines: lines)
        }
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
