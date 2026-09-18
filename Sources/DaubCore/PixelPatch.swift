import CoreGraphics
import Foundation

/// One undo step as *what it changed*: the pixels that were under the area a tool touched,
/// and nothing else.
///
/// A snapshot — even a tile-shared one — remembers the whole picture, so the first step of
/// any history costs a whole canvas (92 MB at 6000x4000). A stroke does not change a whole
/// canvas; it changes a few hundred pixels. A patch is opened before the tool draws, and
/// every drawing call tells it the rectangle it is about to touch: the tiles under that
/// rectangle are copied once, the first time they are touched, and never again for that
/// step. Nothing scales with the size of the picture — only with the size of the edit.
///
/// It is its own inverse. `apply` swaps the stored bytes with what is on the canvas now, so
/// the same object undoes a step and then redoes it, with no second copy anywhere.
public final class PixelPatch {
    public let grid: TileGrid
    private var tiles: [Int: Tile] = [:]

    public var isEmpty: Bool { tiles.isEmpty }
    public var tileCount: Int { tiles.count }
    public var byteCount: Int { tiles.values.reduce(0) { $0 + $1.byteCount } }

    public init(canvas: Bitmap, tileSize: Int = Bitmap.snapshotTileSize) {
        grid = TileGrid(width: canvas.width, height: canvas.height, tileSize: tileSize)
    }

    /// Copy what is under `rect` — in drawing coordinates — unless this step already has it.
    /// Call it *before* the pixels change. Being generous with the rectangle costs a tile,
    /// being short of it costs correctness, so round outwards.
    public func capture(_ bitmap: Bitmap, rect: CGRect) {
        guard grid.matches(bitmap) else { return }
        for (row, column) in grid.tiles(coveringDrawingRect: rect, in: bitmap) {
            let index = grid.index(row: row, column: column)
            guard tiles[index] == nil else { continue }
            tiles[index] = bitmap.tile(row: row, column: column, grid: grid)
        }
    }

    /// For the operations that really do touch everything: invert, clear, a colour swap
    /// across the whole picture.
    public func captureAll(_ bitmap: Bitmap) {
        capture(bitmap, rect: bitmap.bounds)
    }

    /// Put the stored pixels back and take the current ones in their place, so this patch
    /// now redoes what it just undid.
    @discardableResult
    public func apply(to bitmap: Bitmap) -> Bool {
        guard grid.matches(bitmap) else { return false }
        for (index, tile) in tiles {
            let (row, column) = grid.position(of: index)
            let current = bitmap.tile(row: row, column: column, grid: grid)
            bitmap.write(tile, row: row, column: column, grid: grid)
            tiles[index] = current
        }
        return true
    }
}

/// How a canvas is cut into tiles. Shared by the patches and the whole-canvas snapshots so
/// that one set of index arithmetic serves both.
public struct TileGrid: Equatable {
    public let width: Int
    public let height: Int
    public let tileSize: Int
    public let columns: Int
    public let rows: Int

    public init(width: Int, height: Int, tileSize: Int) {
        // Clamped to the canvas as well as to 1: `(width + side - 1)` overflows for a
        // `tileSize` of `Int.max`, and one tile covering everything is the right answer for
        // any size past the canvas anyway.
        let side = max(1, min(tileSize, max(width, height)))
        self.width = width
        self.height = height
        self.tileSize = side
        columns = (width + side - 1) / side
        rows = (height + side - 1) / side
    }

    public func matches(_ bitmap: Bitmap) -> Bool {
        bitmap.width == width && bitmap.height == height
    }

    public func index(row: Int, column: Int) -> Int { row * columns + column }
    public func position(of index: Int) -> (row: Int, column: Int) {
        (index / columns, index % columns)
    }

    /// Tiles overlapping a rectangle given in *drawing* coordinates (origin bottom-left),
    /// which is what every tool works in, while tile rows run top-down like the memory.
    func tiles(coveringDrawingRect rect: CGRect, in bitmap: Bitmap) -> [(Int, Int)] {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard r.width >= 1, r.height >= 1 else { return [] }
        let firstColumn = Int(r.minX) / tileSize
        let lastColumn = (Int(r.maxX) - 1) / tileSize
        let topRow = (height - Int(r.maxY)) / tileSize
        let bottomRow = (height - Int(r.minY) - 1) / tileSize
        var result: [(Int, Int)] = []
        result.reserveCapacity((lastColumn - firstColumn + 1) * (bottomRow - topRow + 1))
        for row in topRow...bottomRow {
            for column in firstColumn...lastColumn { result.append((row, column)) }
        }
        return result
    }
}
