# Daub

A native macOS paint app. Classic-Paint tools, modern finish, no dependencies.

macOS ships no raster paint app — Preview's Markup annotates, Freeform is vector, and the
free simple option (Paintbrush) has been unmaintained for years. Daub fills that gap:
open an image, draw on it, save it.

    Scripts/build-app.sh          # → build/Daub.app  (~800 KB, no frameworks bundled)
    swift test                    # engine tests, no GUI needed

## What's in it

**Tools** — pencil (hard-edged, pixel-exact), brush, airbrush, eraser, flood fill with a
tolerance slider, eyedropper, text, line, rectangle, rounded rectangle, ellipse, and a
rectangular selection you can move, nudge, cut, copy and paste.

**Behaviour that matters**
- Left button paints the foreground colour, right button the background — as in Paint.
- ⇧ constrains: lines to 45°, rectangles to squares, ellipses to circles.
- Bare-letter tool shortcuts (P, B, A, E, F, I, T, L, R, D, C, S), `X` swaps colours,
  `[` / `]` size the current tool.
- Pixel grid appears from 800%; zoom 25%–3200%, or pinch on a trackpad.
- Undo is a 32-step snapshot history covering every tool, transform and canvas resize.
- Canvas Size can crop/extend (anchored top-left) or scale the picture.
- Reads PNG, JPEG, TIFF, BMP, GIF, HEIC, WebP. Writes PNG, JPEG, TIFF.

## Layout

| Path | What it is |
|---|---|
| `Sources/DaubCore/` | The engine — no AppKit, no UI, fully testable: `Bitmap`, `FloodFill`, `Raster`, `Shapes`, `UndoHistory`. |
| `Sources/Daub/Model/` | `Editor` (everything the chrome binds to), `PaintDocument` (pixels + history), `Tool`. |
| `Sources/Daub/Views/` | `CanvasView` (the NSView doing all tool work), SwiftUI toolbox, palette, status bar. |
| `Sources/Daub/IO/` | ImageIO reading and writing, and the pasteboard. |
| `Scripts/build-app.sh` | Assembles the `.app` from the SwiftPM build. No Xcode project. |

## Two design decisions worth knowing

**One coordinate space.** A `CGBitmapContext` stores row 0 as the *top* of the picture but
draws with the origin at the *bottom* left. The raster tools address memory; the brush and
shapes go through CoreGraphics. `Bitmap`'s accessors flip on the way to memory so both
speak drawing coordinates — without that, a pencil stroke lands mirrored against an
identical brush stroke. `CoordinateSpaceTests` pins it.

**SwiftUI never hears about a stroke.** `CanvasView` redraws itself and mutates
`PaintDocument` directly; the chrome is refreshed only at commit boundaries via
`Editor.didCommit()`. Pointer position lives on a separate `CursorReadout` object so a
mouse-move doesn't re-render the window.

## Icon

`Resources/AppIcon.icns` — generated through the hub image router (subscriptions only),
then cropped and re-masked locally to Apple's icon geometry: an 824/1024 content square
with a superellipse (n=5) corner curve and a baked contact shadow, because the model's own
tile edge was ragged. Masters live in the warehouse at
`2d_assets/pictures/icons/app/branding/paintbrush/daub` — both the raw render and the
finished tile, so another project can reuse either.

## Reviewed

A three-seat external panel (OpenAI / xAI / Google, reading the code) went over the first
two commits. Fixed from it: the screen redraw copied the whole canvas every frame;
"Rotate Right" turned the picture left; pasting a transparent PNG punched holes in an
opaque canvas; a save landing mid-airbrush cleared the dirty flag while the spray timer
still painted; ⌘W ran the unsaved-work alert after the window was already gone;
cancelling New/Open still committed a floating selection; a fill that changed nothing
still cost an undo step; the text tool baked its string at the field's frame origin
rather than where the cell drew it; and opening a malformed image could trap on a huge
allocation. `PanelFixTests` pins the testable half. One panel claim — that the pixel grid
double-scales — was wrong: the grid draws after `restoreGState`, unscaled.

## Not there yet

Layers, curve tool, free-form selection, polygon tool, multi-line text boxes (the text
tool is a single line), multiple windows. Document icons (the per-file-type ones) are not drawn yet.
