import CoreGraphics

/// Snapshot undo. A full-canvas CGImage per step is crude but it is also the only model
/// that survives every tool without per-tool inverse logic; the cap keeps memory bounded.
public final class UndoHistory {
    public let limit: Int
    private var past: [CGImage] = []
    private var future: [CGImage] = []

    public init(limit: Int = 32) { self.limit = max(1, limit) }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var depth: Int { past.count }

    /// Call immediately *before* mutating the canvas.
    public func record(_ snapshot: CGImage?) {
        guard let snapshot else { return }
        past.append(snapshot)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    public func undo(current: CGImage?) -> CGImage? {
        guard let previous = past.popLast() else { return nil }
        if let current { future.append(current) }
        return previous
    }

    public func redo(current: CGImage?) -> CGImage? {
        guard let next = future.popLast() else { return nil }
        if let current { past.append(current) }
        return next
    }

    public func clear() { past.removeAll(); future.removeAll() }
}
