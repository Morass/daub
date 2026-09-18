import CoreGraphics

/// One step of history.
///
/// Nearly always a `patch`: the pixels under the area a tool touched, and its own inverse.
/// A `whole` snapshot is kept for the steps that change the *size* of the canvas — a resize,
/// a crop, a rotate, a paste that grows the picture — where "the pixels under this
/// rectangle" has no meaning across the change.
public enum UndoStep {
    case patch(PixelPatch)
    case whole(CanvasSnapshot)

    var tiles: [Tile] {
        switch self {
        case .patch(let patch): return patch.storedTiles
        case .whole(let snapshot): return snapshot.tiles
        }
    }
}

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
    private var past: [UndoStep] = []
    private var future: [UndoStep] = []

    /// - Parameter byteBudget: 512 MB by default — about five whole-canvas steps of a
    ///   24-megapixel picture, or an unbounded number of ordinary strokes.
    public init(limit: Int = 32, byteBudget: Int = 512 << 20) {
        self.limit = max(1, limit)
        self.byteBudget = max(1 << 20, byteBudget)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var depth: Int { past.count }

    /// The newest whole-canvas snapshot on the undo side, for a new one to share tiles
    /// with. Pass it to `Bitmap.snapshot(reusing:)`.
    public var newestPastSnapshot: CanvasSnapshot? {
        for step in past.reversed() { if case .whole(let snapshot) = step { return snapshot } }
        return nil
    }

    /// Distinct bytes actually held, counting a tile shared by twenty snapshots once.
    public var byteCount: Int {
        var seen = Set<ObjectIdentifier>()
        var total = 0
        for step in past {
            for tile in step.tiles where seen.insert(ObjectIdentifier(tile)).inserted {
                total += tile.byteCount
            }
        }
        for step in future {
            for tile in step.tiles where seen.insert(ObjectIdentifier(tile)).inserted {
                total += tile.byteCount
            }
        }
        // The steps held aside for a rollback are still in memory, so they still count.
        for step in (lastRecordUndid.map { $0.evicted + $0.clearedFuture } ?? []) {
            for tile in step.tiles where seen.insert(ObjectIdentifier(tile)).inserted {
                total += tile.byteCount
            }
        }
        return total
    }

    /// What the last `record` cost, so that cancelling it can be a true rollback: the redo
    /// branch it cleared and the old steps its trim evicted. Without this, a click that
    /// turned out to change nothing could leave the user with *fewer* undo steps than
    /// before they clicked — on a big canvas, with none at all.
    private var lastRecordUndid: (evicted: [UndoStep], clearedFuture: [UndoStep])?

    /// Open a step. Call immediately *before* mutating the canvas.
    public func record(_ step: UndoStep) {
        let clearedFuture = future
        future.removeAll()
        past.append(step)
        lastRecordUndid = (trim(), clearedFuture)
    }

    /// Swap the step just recorded for another — how a step that turns out to change the
    /// size of the canvas becomes a whole-canvas one.
    public func replaceNewestStep(with step: UndoStep) {
        guard !past.isEmpty else { return }
        past[past.count - 1] = step
        // The swap can push the history over budget, and what that evicts belongs to the
        // same rollback as the step itself: cancelling it must put those steps back too.
        let evicted = trim()
        if !evicted.isEmpty, let undone = lastRecordUndid {
            lastRecordUndid = (undone.evicted + evicted, undone.clearedFuture)
        }
    }

    /// Bring the history back inside its budget now that the step just recorded has
    /// finished growing. A patch is empty when it is recorded and fills as the tool draws,
    /// so the check at record time sees none of its weight.
    public func enforceBudget() { _ = trim() }

    /// - Parameter apply: put the step's pixels on the canvas and hand back the step that
    ///   reverses it — a patch is its own inverse; a whole-canvas snapshot needs the canvas
    ///   as it was a moment ago. Returning nil leaves the history untouched.
    public func undo(applying apply: (UndoStep) -> UndoStep?) -> Bool {
        guard let step = past.popLast() else { return false }
        guard let inverse = apply(step) else { past.append(step); return false }
        future.append(inverse)
        lastRecordUndid = nil
        _ = trim()
        return true
    }

    public func redo(applying apply: (UndoStep) -> UndoStep?) -> Bool {
        guard let step = future.popLast() else { return false }
        guard let inverse = apply(step) else { future.append(step); return false }
        past.append(inverse)
        lastRecordUndid = nil
        _ = trim()
        return true
    }

    /// Throw away the checkpoint just recorded, for an action that turned out to change
    /// nothing — filling an area with the colour it already is, say. Without this, every
    /// misfired click costs the user a press of ⌘Z.
    @discardableResult
    public func discardLastCheckpoint() -> Bool {
        guard past.popLast() != nil else { return false }
        rollBackTheLastRecording()
        return true
    }

    /// Cancel the step just recorded *and* put its pixels back — Escape on a paste, or on a
    /// selection that was moved. Unlike an undo this leaves no redo entry and does not touch
    /// the redo branch that was already there: the step never happened.
    ///
    /// - Parameter apply: put the step's pixels back on the canvas; false leaves everything
    ///   alone.
    @discardableResult
    public func cancelLastCheckpoint(applying apply: (UndoStep) -> Bool) -> Bool {
        guard let step = past.last, apply(step) else { return false }
        past.removeLast()
        rollBackTheLastRecording()
        return true
    }

    private func rollBackTheLastRecording() {
        guard let undone = lastRecordUndid else { return }
        past.insert(contentsOf: undone.evicted, at: 0)
        future = undone.clearedFuture
        lastRecordUndid = nil
    }

    public func clear() { past.removeAll(); future.removeAll(); lastRecordUndid = nil }

    /// Enforce both ceilings. Over budget, the step dropped is the one furthest from the
    /// present — the oldest undo, or the deepest redo — taken from whichever stack is
    /// longer, so a long run of undos cannot park all the memory in the redo branch.
    ///
    /// The step nearest the present on *each* side is never dropped, whatever it costs:
    /// one ⌘Z and one ⇧⌘Z always work. A single snapshot can exceed the whole budget (a
    /// 8192 x 8192 canvas is 268 MB), and taking the user's only undo away to satisfy a
    /// number they cannot see is the worse trade.
    ///
    /// - Returns: the undo steps it evicted, oldest first, so a cancelled checkpoint can
    ///   put them back.
    @discardableResult
    private func trim() -> [UndoStep] {
        var evicted: [UndoStep] = []
        if past.count > limit {
            evicted.append(contentsOf: past.prefix(past.count - limit))
            past.removeFirst(past.count - limit)
        }
        if future.count > limit { future.removeFirst(future.count - limit) }
        while byteCount > byteBudget {
            let canDropPast = past.count > 1
            let canDropFuture = future.count > 1
            if canDropPast, !canDropFuture || past.count >= future.count {
                evicted.append(past.removeFirst())
            } else if canDropFuture {
                future.removeFirst()
            } else if lastRecordUndid != nil {
                // Last resort: let go of the steps held aside in case the newest checkpoint
                // is cancelled. Cancelling then still puts the pixels back; what it can no
                // longer do is resurrect the steps that recording it evicted.
                lastRecordUndid = nil
            } else {
                break
            }
        }
        return evicted
    }
}
