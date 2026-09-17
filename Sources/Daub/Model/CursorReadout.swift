import CoreGraphics
import SwiftUI

/// Pointer position and selection size, kept off `Editor` on purpose.
///
/// These change on every mouse-moved event. If they lived on `Editor` the whole window
/// would re-render whenever the pointer twitched; here only the status bar does.
@MainActor
final class CursorReadout: ObservableObject {
    @Published var pixel: CGPoint?
    @Published var selection: CGSize?
}
