// Draws the picture at the top of the README, using nothing but DaubCore — the same engine
// the app paints with. Deliberately wobbly: every stroke is jittered, the colour sits under
// the outline instead of inside it, and nothing lines up. A tidy logo would say less about
// what the app is for.
//
//   swift build
//   swiftc -O -I .build/debug -L .build/debug -lDaubCore \
//          Scripts/make-readme-art.swift -o .build/make-readme-art && .build/make-readme-art out.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import DaubCore

/// Seeded, so the picture is the same every time the README is rebuilt.
struct Crayon: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func wobble(_ amount: Double) -> Double { Double.random(in: -amount...amount, using: &self) }
}

var rng = Crayon(seed: 0x0DAB_0DAB)

let W = 1000, H = 420
let paper = Bitmap(width: W, height: H, fill: CGColor(srgbRed: 1, green: 0.992, blue: 0.972, alpha: 1))

func rgba(_ r: Int, _ g: Int, _ b: Int) -> RGBA { RGBA(r: UInt8(r), g: UInt8(g), b: UInt8(b)) }

let ink     = rgba(38, 34, 44)
let red     = rgba(226, 74, 63)
let blue    = rgba(58, 120, 208)
let yellow  = rgba(247, 196, 62)
let green   = rgba(76, 172, 108)
let violet  = rgba(150, 92, 186)

/// A stroke a hand made: subdivided, nudged off course at every joint, and thickening and
/// thinning as it goes.
func crayonLine(from a: CGPoint, to b: CGPoint, width: Int, colour: RGBA, waver: Double = 3.2) {
    let steps = max(4, Int(hypot(b.x - a.x, b.y - a.y) / 14))
    var previous = a
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        var next = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        if i < steps { next.x += rng.wobble(waver); next.y += rng.wobble(waver) }
        Raster.line(paper, from: (Int(previous.x), Int(previous.y)), to: (Int(next.x), Int(next.y)),
                    size: max(2, width + Int(rng.wobble(1.4))), color: colour)
        previous = next
    }
}

/// A closed shape drawn the same way — the ends never quite meet, which is the point.
func crayonArc(centre: CGPoint, radius: CGFloat, from startDeg: Double, to endDeg: Double,
               width: Int, colour: RGBA, squash: CGFloat = 1) {
    let steps = max(8, Int((endDeg - startDeg).magnitude / 9))
    var points: [CGPoint] = []
    for i in 0...steps {
        let angle = (startDeg + (endDeg - startDeg) * Double(i) / Double(steps)) * .pi / 180
        let r = radius + CGFloat(rng.wobble(2.6))
        points.append(CGPoint(x: centre.x + cos(angle) * r,
                              y: centre.y + sin(angle) * r * squash))
    }
    for i in 1..<points.count {
        Raster.line(paper, from: (Int(points[i - 1].x), Int(points[i - 1].y)),
                    to: (Int(points[i].x), Int(points[i].y)),
                    size: max(2, width + Int(rng.wobble(1.2))), color: colour)
    }
}

/// The colour a child puts down first and then draws over, never quite inside the lines.
func blotch(centre: CGPoint, radius: CGFloat, colour: RGBA, squash: CGFloat = 1) {
    let ctx = paper.context
    let path = CGMutablePath()
    let steps = 26
    for i in 0...steps {
        let angle = Double(i) / Double(steps) * 2 * .pi
        let r = radius * CGFloat(1 + rng.wobble(0.13))
        let p = CGPoint(x: centre.x + CGFloat(cos(angle)) * r,
                        y: centre.y + CGFloat(sin(angle)) * r * squash)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    ctx.saveGState()
    ctx.setFillColor(colour.cgColor.copy(alpha: 0.82) ?? colour.cgColor)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

/// Colour that only reaches the bottom of a letter, so a `u` does not fill in solid.
func halfBlotch(centre: CGPoint, radius: CGFloat, colour: RGBA) {
    let ctx = paper.context
    let path = CGMutablePath()
    let steps = 20
    for i in 0...steps {
        let angle = .pi + Double(i) / Double(steps) * .pi
        let r = radius * CGFloat(1 + rng.wobble(0.12))
        let p = CGPoint(x: centre.x + CGFloat(cos(angle)) * r,
                        y: centre.y + CGFloat(sin(angle)) * r)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    ctx.saveGState()
    ctx.setFillColor(colour.cgColor.copy(alpha: 0.82) ?? colour.cgColor)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

// ── the word ────────────────────────────────────────────────────────────────────────────
// d a u b. Coordinates are bottom-up, like the canvas itself: baseline at y = 120, bowls
// around y = 175, ascenders up to y = 320. The colour goes down first and sits a few pixels
// off from the outline that follows it, because that is what colouring in looks like when
// you are five.

// d — a filled bowl with the stem running past the top of it
blotch(centre: CGPoint(x: 156, y: 172), radius: 54, colour: yellow, squash: 0.95)
crayonArc(centre: CGPoint(x: 150, y: 176), radius: 55, from: 0, to: 352, width: 8, colour: ink)
crayonLine(from: CGPoint(x: 196, y: 108), to: CGPoint(x: 203, y: 322), width: 8, colour: ink)

// a — the same bowl, a stem that stops at the x-height and then overshoots anyway
blotch(centre: CGPoint(x: 336, y: 170), radius: 51, colour: red, squash: 0.93)
crayonArc(centre: CGPoint(x: 332, y: 175), radius: 52, from: 8, to: 358, width: 8, colour: ink)
crayonLine(from: CGPoint(x: 377, y: 110), to: CGPoint(x: 374, y: 240), width: 8, colour: ink)

// u — colour only in the bottom half, so the letter stays open at the top
halfBlotch(centre: CGPoint(x: 524, y: 168), radius: 52, colour: blue)
crayonArc(centre: CGPoint(x: 520, y: 172), radius: 52, from: 182, to: 358, width: 8, colour: ink)
crayonLine(from: CGPoint(x: 468, y: 172), to: CGPoint(x: 464, y: 246), width: 8, colour: ink)
crayonLine(from: CGPoint(x: 572, y: 168), to: CGPoint(x: 576, y: 252), width: 8, colour: ink)

// b — the tall one, drawn last and in a hurry
blotch(centre: CGPoint(x: 726, y: 170), radius: 52, colour: green, squash: 0.95)
crayonArc(centre: CGPoint(x: 722, y: 174), radius: 53, from: 8, to: 350, width: 8, colour: ink)
crayonLine(from: CGPoint(x: 676, y: 104), to: CGPoint(x: 681, y: 326), width: 8, colour: ink)

// ── the brush, held at the wrong angle ──────────────────────────────────────────────────
crayonLine(from: CGPoint(x: 958, y: 302), to: CGPoint(x: 914, y: 216), width: 13, colour: ink, waver: 2.2)
crayonLine(from: CGPoint(x: 900, y: 210), to: CGPoint(x: 930, y: 196), width: 8, colour: ink, waver: 1.0)
crayonLine(from: CGPoint(x: 895, y: 199), to: CGPoint(x: 925, y: 185), width: 8, colour: ink, waver: 1.0)
crayonLine(from: CGPoint(x: 906, y: 194), to: CGPoint(x: 894, y: 166), width: 7, colour: ink, waver: 1.6)
crayonLine(from: CGPoint(x: 916, y: 190), to: CGPoint(x: 908, y: 162), width: 7, colour: ink, waver: 1.6)
blotch(centre: CGPoint(x: 900, y: 146), radius: 25, colour: violet, squash: 1.05)
crayonArc(centre: CGPoint(x: 900, y: 146), radius: 25, from: 0, to: 350, width: 6, colour: ink)

// ── the drip, because paint does that ───────────────────────────────────────────────────
crayonLine(from: CGPoint(x: 897, y: 126), to: CGPoint(x: 893, y: 86), width: 7, colour: violet, waver: 1.8)
blotch(centre: CGPoint(x: 892, y: 76), radius: 12, colour: violet)

// ── specks off the end of the brush ─────────────────────────────────────────────────────
for (x, y, r, colour) in [(268, 330, 15, red), (452, 344, 13, yellow), (612, 336, 12, blue),
                          (800, 300, 11, green), (118, 300, 12, violet), (398, 66, 10, green),
                          (640, 60, 9, red)] {
    Raster.spray(paper, x: x, y: y, radius: r, density: 90, color: colour, using: &rng)
}

// ── the underline that runs out of steam ────────────────────────────────────────────────
crayonLine(from: CGPoint(x: 126, y: 62), to: CGPoint(x: 812, y: 76), width: 9, colour: blue, waver: 5)

// ── write it out ────────────────────────────────────────────────────────────────────────
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "readme-art.png")
guard let image = paper.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not render") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path)")
