import CoreGraphics

/// Snapshot undo, over tiles instead of whole images.
///
/// A snapshot per step is still the only model that survives every tool without per-tool
/// inverse logic, but a *full* snapshot per step made the price of that absurd: thirty-two
/// steps of a 6000x4000 canvas is 3 GB, for a history whose steps are nearly always a
/// stroke over a few hundred pixels. Each snapshot here is a grid of shared tiles
/// (`CanvasSnapshot`), so a step costs only the tiles it changed.
///
/// Two ceilings hold it: `limit` steps, and `byteBudget` bytes of distinct tile data.
/// Whole-canvas steps — invert, a full-canvas paste — really do cost a canvas each, and
/// the budget is what stops thirty-two of those from filling memory. Dropping the oldest
/// step is the honest response; refusing the edit is not.
public final class UndoHistory {
    public let limit: Int
    public let byteBudget: Int
    private var past: [CanvasSnapshot] = []
    private var future: [CanvasSnapshot] = []

    /// - Parameter byteBudget: 512 MB by default — about five whole-canvas steps of a
    ///   24-megapixel picture, or an unbounded number of ordinary strokes.
    public init(limit: Int = 32, byteBudget: Int = 512 << 20) {
        self.limit = max(1, limit)
        self.byteBudget = max(1 << 20, byteBudget)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var depth: Int { past.count }

    /// The snapshot a new capture should share tiles with: the one immediately before it
    /// in time. Pass it to `Bitmap.snapshot(reusing:)`.
    public var newestPast: CanvasSnapshot? { past.last }
    public var newestFuture: CanvasSnapshot? { future.last }

    /// Distinct bytes actually held, counting a tile shared by twenty snapshots once.
    public var byteCount: Int {
        var seen = Set<ObjectIdentifier>()
        var total = 0
        for snapshot in past {
            for tile in snapshot.tiles where seen.insert(ObjectIdentifier(tile)).inserted {
                total += tile.byteCount
            }
        }
        for snapshot in future {
            for tile in snapshot.tiles where seen.insert(ObjectIdentifier(tile)).inserted {
                total += tile.byteCount
            }
        }
        return total
    }

    /// Call immediately *before* mutating the canvas.
    public func record(_ snapshot: CanvasSnapshot?) {
        guard let snapshot else { return }
        past.append(snapshot)
        future.removeAll()
        trim()
    }

    public func undo(current: CanvasSnapshot?) -> CanvasSnapshot? {
        guard let previous = past.popLast() else { return nil }
        if let current { future.append(current) }
        trim()
        return previous
    }

    public func redo(current: CanvasSnapshot?) -> CanvasSnapshot? {
        guard let next = future.popLast() else { return nil }
        if let current { past.append(current) }
        trim()
        return next
    }

    /// Throw away the checkpoint just recorded, for an action that turned out to change
    /// nothing — filling an area with the colour it already is, say. Without this, every
    /// misfired click costs the user a press of ⌘Z.
    @discardableResult
    public func discardLastCheckpoint() -> Bool {
        past.popLast() != nil
    }

    public func clear() { past.removeAll(); future.removeAll() }

    /// Enforce both ceilings. Over budget, the step dropped is the one furthest from the
    /// present — the oldest undo, or the deepest redo — taken from whichever stack is
    /// longer, so a long run of undos cannot park all the memory in the redo branch.
    /// One undo step always survives: with nothing to trade, keeping it beats keeping none.
    private func trim() {
        if past.count > limit { past.removeFirst(past.count - limit) }
        if future.count > limit { future.removeFirst(future.count - limit) }
        while byteCount > byteBudget {
            if past.count > 1, past.count >= future.count {
                past.removeFirst()
            } else if !future.isEmpty {
                future.removeFirst()
            } else {
                break
            }
        }
    }
}
