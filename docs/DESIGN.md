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

## Fixed: the canvas redrew as it was before a whole-canvas operation

Reported 2026-09-18 as "squares around the whole trail" after gradient → brush → pencil.

`Bitmap.liveImage` handed back **one cached `CGImage`** for the life of the buffer.
CoreGraphics treats a `CGDataProvider` over raw memory as immutable and caches the raster
it uploads for an image, keyed on the image, so the full-canvas redraw in
`CanvasView.draw(_:)` kept painting the first raster it ever saw. The partial path escaped
it because `CGImage.cropping` mints a new image every call.

On screen that read as: apply a gradient and the canvas still looks like the old picture;
draw over it and the gradient appears only inside the dirty rectangles the stroke
repainted, in blocks tracing the stroke. The pixels were correct the whole time — the
saved file and any fresh redraw were fine, which is why it could not be reproduced by
rendering the document offscreen.

Fix: `liveImage` mints a new `CGImage` per call. It copies nothing — a provider and an
image header are pointer work — so the zero-copy redraw is intact. The stale-cache helper
`cachedLiveImageIsStale()` is gone with the cache. Pinned by
`testLiveImageIsNotCachedBetweenCalls`.

**Known minor, not fixed:** at a fractional zoom (⌘0 *Fit in window* rounds to 1%) a
partial repaint differs from a full one by 1–2 levels per channel along the patch edges —
measured, invisible on flat artwork, a faint seam across a smooth gradient. Clipping
instead of cropping gives the same seams, so it is partial repaint at a non-integer scale,
not the crop. The fix would be snapping zoom to whole multiples of `1/backingScaleFactor`.
