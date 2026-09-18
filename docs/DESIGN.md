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

**Snapshot undo, over shared tiles.** A snapshot before each mutation still — it is the
only model that survives every tool without per-tool inverse logic — but a snapshot is a
grid of 128×128 tiles (`CanvasSnapshot`), and taking one reuses, by reference, every tile
whose bytes are unchanged (`memcmp` per tile row against live memory, no allocation for a
tile that matches). A stroke therefore costs the tiles it crossed, not the canvas: 33
steps on 6000×4000 is **92 MB where full images cost 3.0 GB**. Capture is ~8.7 ms on that
canvas, once per stroke at mouse-down, against ~0.3 ms for a 1024×768 one.

Two ceilings: 32 steps and a 512 MB budget of distinct tile bytes. Whole-canvas steps
(invert, a full-canvas paste) genuinely cost a canvas each, and the budget is what stops
thirty-two of those from filling memory — it drops the step furthest from the present,
from whichever of the undo/redo stacks is longer, and always keeps one. Measured: 40
inverts of 6000×4000 settle at 458 MB / 5 steps instead of 3.7 GB.

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
