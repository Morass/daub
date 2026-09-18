# Daub — internals

Not user-facing. The README is installation, guide and examples only; everything about
how Daub is built lives here.

## Layout

| Path | What it is |
|---|---|
| `Sources/DaubCore/` | The engine — no AppKit, no UI, fully testable: `Bitmap`, `FloodFill`, `Raster`, `Shapes`, `UndoHistory`. |
| `Sources/Daub/Model/` | `Editor` (everything the chrome binds to), `PaintDocument` (pixels + history), `Tool`. |
| `Sources/Daub/Views/` | `CanvasView` (the NSView doing all tool work), SwiftUI toolbox, palette, status bar. |
| `Sources/Daub/IO/` | ImageIO reading and writing, and the pasteboard. |
| `Scripts/build-app.sh` | Assembles the `.app` from the SwiftPM build. |
| `Scripts/install.sh` | The above, plus install and un-quarantine. |
| `Scripts/make-readme-art.swift` | Paints the README artwork with `DaubCore` (`make readme-art`). |

`make test` runs the engine tests with no GUI. `make screenshot` has the app render its own
window into a PNG — no screen recording, no permission dialog, so it works on a headless
build machine.

## Three decisions worth knowing

**One coordinate space.** A `CGBitmapContext` stores row 0 as the *top* of the picture but
draws with the origin at the *bottom* left. The raster tools address memory; the brush and
shapes go through CoreGraphics. `Bitmap`'s accessors flip on the way to memory so both
speak drawing coordinates — without that, a pencil stroke lands mirrored against an
identical brush stroke. `CoordinateSpaceTests` pins it.

**SwiftUI never hears about a stroke.** `CanvasView` redraws itself and mutates
`PaintDocument` directly; the chrome refreshes only at commit boundaries via
`Editor.didCommit()`. Pointer position lives on a separate `CursorReadout` object so a
mouse-move doesn't re-render the window. The screen draw reads *through* the bitmap's
buffer (`liveImage`) and blits only the dirty region, rather than copying the canvas each
frame.

**Snapshot undo.** 32 full-canvas snapshots, taken before each mutation. Crude, but it
survives every tool without per-tool inverse logic. The cap is a step count, not a byte
budget — 32 steps of a 4096² canvas is about 2 GB.

## External review, first two commits

A three-seat panel (OpenAI / xAI / Google, reading the code) went over the first two
commits. Fixed from it: the screen redraw copied the whole canvas every frame; "Rotate
Right" turned the picture left; pasting a transparent PNG punched holes in an opaque
canvas; a save landing mid-airbrush cleared the dirty flag while the spray timer still
painted; the unsaved-work alert ran after the window had already closed; cancelling
New/Open still committed a floating selection; a fill that changed nothing still cost an
undo step; the text tool baked its string at the field's frame origin rather than where the
cell drew it; and opening a malformed image could trap on a huge allocation. One panel
claim — that the pixel grid double-scales — was wrong: the grid draws after
`restoreGState`, unscaled.

## Not implemented

**Layers.** The single biggest absence. Everything here assumes one bitmap.

**Mask-based selection** — magic wand, lasso, "select by colour". The selection is a
rectangle; making it a mask touches lift, move, paste, crop and every clip in the app.

**Also absent:** smudge, blur and sharpen brushes; the curve and polygon tools; free
rotate and scale of a selection; levels and curves adjustments; brush shapes beyond round
and square; multi-line text boxes (the text tool is a single line); multiple windows and
documents; document icons for file types.

## Open bug: rectangles visible around a stroke drawn over a gradient

Reported 2026-09-18. Verified: the **pixels are clean** — rendering the document after a
gradient plus brush strokes shows no artefact, so nothing is writing squares into the
bitmap. The artefact is in the incremental screen repaint: `CanvasView.draw(_:)` blits only
the dirty rectangle (`Bitmap.croppedLiveImage`), and the dirty rects chain along the stroke.

Measured in isolation: at an integer zoom the partial blit is bit-identical to a full draw;
at a fractional zoom (1.5, 0.75 — what ⌘0 *Fit in window* produces, it rounds to 1%) the
patch edges differ from a full draw by 1–2 levels per channel. Invisible on flat artwork,
visible as seams against a smooth gradient. Clipping and drawing the whole image instead of
cropping gives the same seams, so cropping is not the cause — partial repaint at a
non-integer scale is.

Candidate fixes, none applied yet: snap zoom to whole multiples of `1/backingScaleFactor`
so canvas pixels map to whole device pixels; or force a full redraw while the canvas is at
a fractional zoom. Not yet confirmed to be the whole of what the reporter sees — the
remaining suspect is `Bitmap.cachedLiveImage`, a `CGImage` held over live memory that is
dropped only on the two paths that bypass the `CGContext` (`clearAll`, `replaceColour`).
