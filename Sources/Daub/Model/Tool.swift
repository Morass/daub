import DaubCore
import SwiftUI

enum Tool: String, CaseIterable, Identifiable, Sendable {
    case select, pencil, brush, airbrush, eraser, fill, picker, text
    case clone, colourReplace, gradient
    case line, rectangle, roundedRectangle, ellipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .pencil: "Pencil"
        case .brush: "Brush"
        case .airbrush: "Airbrush"
        case .eraser: "Eraser"
        case .fill: "Fill"
        case .picker: "Pick Colour"
        case .text: "Text"
        case .clone: "Clone Stamp"
        case .colourReplace: "Replace Colour"
        case .gradient: "Gradient"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .roundedRectangle: "Rounded Rectangle"
        case .ellipse: "Ellipse"
        }
    }

    /// One line for the in-app help window. Written as "what it does, then the thing you
    /// would otherwise have to discover by accident".
    var help: String {
        switch self {
        case .select:
            "Drag a rectangle, then drag inside it to move the pixels. ⌥-drag leaves a copy behind. ⌘D deselects, ⌘⇧K crops to the selection."
        case .pencil:
            "Hard single-pixel freehand, no antialiasing. The tool for pixel art and for touching up one pixel at 800%."
        case .brush:
            "Soft round freehand. Size and Opacity apply; Smooth edges makes diagonals look smooth instead of stepped."
        case .airbrush:
            "Sprays while you hold the button, so it builds up if you dwell. Radius sets the spread, Density how fast it lands."
        case .eraser:
            "Rubs back to the background colour — or to nothing at all on a canvas that has transparency."
        case .fill:
            "Flood-fills the area under the click. Raise Tolerance when a photo or JPEG leaves speckles behind."
        case .picker:
            "Takes the colour under the click into the foreground swatch; right-click takes it into the background. Snaps back to your previous tool afterwards."
        case .text:
            "Click, type, press ⏎ to stamp it into the picture. Escape cancels. Once stamped it is pixels, not text, so set the font and size first."
        case .clone:
            "⌥-click to set the source, then paint to copy from it. The source moves with your stroke, keeping the offset."
        case .colourReplace:
            "Click a colour to swap every pixel of it for the foreground colour; right-click swaps to the background colour. Tolerance widens the match, a selection limits where it applies."
        case .gradient:
            "Drag to blend from the foreground colour to the background colour along the drag."
        case .line:
            "Drag for a straight line. Hold ⇧ to snap to 45°."
        case .rectangle, .roundedRectangle, .ellipse:
            "Drag out the shape. Hold ⇧ for a square or circle. Fill style chooses outline, filled, or both; the outline uses the foreground colour and the fill the background one."
        }
    }

    /// SF Symbol name, or nil for the shape tools, which get a hand-drawn vector glyph:
    /// a real rectangle reads better at 16pt than any symbol that approximates one.
    var symbol: String? {
        switch self {
        case .select: "rectangle.dashed"
        case .pencil: "pencil.tip"
        case .brush: "paintbrush.pointed"
        case .airbrush: nil          // no spray can in SF Symbols; drawn in ToolIcon
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .picker: "eyedropper"
        case .text: "textformat"
        case .clone: "stamp"
        case .colourReplace: "paintpalette"
        case .gradient: nil
        case .line, .rectangle, .roundedRectangle, .ellipse: nil
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .select: "s"
        case .pencil: "p"
        case .brush: "b"
        case .airbrush: "a"
        case .eraser: "e"
        case .fill: "f"
        case .picker: "i"
        case .text: "t"
        case .clone: "k"
        case .colourReplace: "g"
        case .gradient: "y"
        case .line: "l"
        case .rectangle: "r"
        case .roundedRectangle: "d"
        case .ellipse: "c"
        }
    }

    var shapeKind: ShapeKind? {
        switch self {
        case .line: .line
        case .rectangle: .rectangle
        case .roundedRectangle: .roundedRectangle
        case .ellipse: .ellipse
        default: nil
        }
    }

    var isShape: Bool { shapeKind != nil }

    /// Tools whose size slider is meaningful, and which knob they read.
    var sizeKnob: SizeKnob? {
        switch self {
        case .pencil: .pencil
        case .brush, .clone, .line, .rectangle, .roundedRectangle, .ellipse: .stroke
        case .eraser: .eraser
        case .airbrush: .spray
        default: nil
        }
    }
}

enum SizeKnob { case pencil, stroke, eraser, spray }

extension Tool {
    /// The outline the cursor draws for tools that paint with a width. Fill, picker,
    /// text and the selection keep their system cursors.
    var cursorTip: BrushCursor.Tip? {
        switch sizeKnob {
        case .pencil, .eraser: .square
        case .stroke: .circle
        case .spray: .spray
        case nil: nil
        }
    }
}

extension Editor {
    /// The size setting the current tool paints with.
    var toolSize: Double {
        switch tool.sizeKnob {
        case .pencil: pencilSize
        case .stroke: strokeWidth
        case .eraser: eraserSize
        case .spray: sprayRadius
        case nil: 0
        }
    }
}

extension Tool {
    /// Each tool carries its own colour so the toolbox reads as a set of instruments
    /// rather than a grid of grey glyphs — the same trick a real paintbox plays. Kept
    /// muted and consistent in hue so the selected state (a solid accent tile) still wins.
    var tint: Color {
        switch self {
        case .select: Color(red: 0.42, green: 0.45, blue: 0.52)
        case .pencil: Color(red: 0.86, green: 0.62, blue: 0.16)
        case .brush: Color(red: 0.20, green: 0.45, blue: 0.82)
        case .airbrush: Color(red: 0.24, green: 0.66, blue: 0.76)
        case .eraser: Color(red: 0.90, green: 0.45, blue: 0.48)
        case .fill: Color(red: 0.31, green: 0.58, blue: 0.86)
        case .picker: Color(red: 0.36, green: 0.68, blue: 0.47)
        case .text: Color(red: 0.45, green: 0.40, blue: 0.62)
        case .clone: Color(red: 0.62, green: 0.48, blue: 0.36)
        case .colourReplace: Color(red: 0.78, green: 0.38, blue: 0.62)
        case .gradient: Color(red: 0.30, green: 0.52, blue: 0.78)
        case .line: Color(red: 0.55, green: 0.52, blue: 0.60)
        case .rectangle: Color(red: 0.36, green: 0.55, blue: 0.70)
        case .roundedRectangle: Color(red: 0.40, green: 0.60, blue: 0.62)
        case .ellipse: Color(red: 0.52, green: 0.50, blue: 0.74)
        }
    }

    /// Tools whose edges CoreGraphics anti-aliases. The pencil, eraser, airbrush and the
    /// pixel-exact tools ignore the setting entirely, so the checkbox is hidden for them
    /// rather than shown doing nothing.
    var honoursAntialiasing: Bool {
        switch self {
        case .brush, .clone, .line, .rectangle, .roundedRectangle, .ellipse: true
        default: false
        }
    }

    var usesOpacity: Bool {
        switch self {
        case .brush, .airbrush, .line, .rectangle, .roundedRectangle, .ellipse: true
        default: false
        }
    }
}
