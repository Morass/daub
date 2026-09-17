import DaubCore
import SwiftUI

enum Tool: String, CaseIterable, Identifiable, Sendable {
    case select, pencil, brush, airbrush, eraser, fill, picker, text
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
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .roundedRectangle: "Rounded Rectangle"
        case .ellipse: "Ellipse"
        }
    }

    /// SF Symbol name, or nil for the shape tools, which get a hand-drawn vector glyph:
    /// a real rectangle reads better at 16pt than any symbol that approximates one.
    var symbol: String? {
        switch self {
        case .select: "rectangle.dashed"
        case .pencil: "pencil.tip"
        case .brush: "paintbrush.pointed"
        case .airbrush: "circle.dotted"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .picker: "eyedropper"
        case .text: "textformat"
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
        case .brush, .line, .rectangle, .roundedRectangle, .ellipse: .stroke
        case .eraser: .eraser
        case .airbrush: .spray
        default: nil
        }
    }
}

enum SizeKnob { case pencil, stroke, eraser, spray }
