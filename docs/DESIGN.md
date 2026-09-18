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

`make selftest` is the layer `swift test` cannot reach: `Support/SelfTest.swift` runs
inside the real app (`DAUB_SELFTEST=clipboard`) and drives the actual paste path — canvas
growth, top-left placement, single-step undo, the clipboard import — then exits non-zero on
the first failure. The pure geometry it depends on (`DaubCore/CanvasFit`) is unit-tested
separately, because that is where the nasty cases live: per-axis growth, the pixel budget,
and CGFloat values that trap on the way to `Int`.

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

**Undo remembers what a step changed.** A step is a `PixelPatch`: opened before the tool
draws, told by each drawing call the rectangle it is about to touch (the same rectangle that
call already computes for the screen redraw), and holding the 64×64 tiles under those
rectangles as they were — copied once, on first touch. It is its own inverse: `apply` swaps
its bytes with the canvas, so the same object undoes a step and then redoes it. Nothing
scales with the size of the picture. 33 strokes on 6000×4000 cost **2.97 MB**; whole-canvas
snapshots cost 92 MB for the same history, and full CGImages cost 3.0 GB. Recording one is
0.02 ms.

`CanvasSnapshot` — the tile grid of the whole canvas, sharing by reference every tile a step
did not change — remains for the steps a patch cannot express: resize, scale, crop, rotate,
and a paste that grows the canvas (`promoteCheckpointToWholeCanvas` swaps the open patch for
one). Those cost the old canvas, which is inherent.

Two ceilings on the history: 32 steps and a 512 MB budget of distinct tile bytes. Over
budget it drops the step furthest from the present, from whichever of the undo/redo stacks
is longer, and never the nearest step on either side.

**The risk this design carries** is a tool that draws somewhere it did not declare: wrong
pixels after an undo, with nothing to see at the time. `PaintDocument.verifiesUndo` keeps a
full snapshot beside every patch and compares them after the undo; the self-test turns it on
and drives every tool — pencil, brush, eraser, airbrush, the four shapes, gradient, fill,
clone stamp, text, and the whole-picture operations — through real mouse events. Deleting
any single `willTouch` call makes those checks fail. Add a tool, add it there.

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

## Clipboard

Two entry points, deliberately different:

- **⌘V** goes through `CanvasView.pasteFromClipboard`. It checkpoints, asks
  `CanvasFit.grown` whether the canvas has to grow, grows it with
  `PaintDocument.growCanvas` (which takes no checkpoint of its own, so the grow and the
  paste are one undo step), then floats the image at the top left.
- **⇧⌘V** is `Editor.newFromClipboard`: a whole new document at the clipboard image's
  size, dirty from birth, shrink-zoomed to fit the window. It asks about unsaved work,
  because it throws the old picture away.

A clipboard image no allocatable canvas could hold leaves the canvas as it is rather than
growing to the 67 Mpx limit and clipping anyway.

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
