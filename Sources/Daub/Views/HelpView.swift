import AppKit
import SwiftUI

/// The manual, inside the app. Everything here is generated from the same `Tool` values the
/// toolbox uses, so a tool can never appear in one and not the other, and the search field
/// filters every row at once — the question people actually arrive with is "how do I make
/// the background transparent", not "which section covers alpha".
struct HelpView: View {
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if hit(Self.intro) { introSection }
                    toolSection
                    keySection
                    recipeSection
                    if isEmptyResult {
                        Text("Nothing here matches “\(query)”.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Daub Help").font(.system(size: 13, weight: .semibold))
                Text("Tools, keys and recipes").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: Sections

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading("Getting started")
            Text(Self.intro)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var toolSection: some View {
        let tools = Tool.allCases.filter {
            hit("\($0.title) \($0.help) \($0.shortcut.character)")
        }
        return Group {
            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("Tools")
                    ForEach(tools) { tool in
                        HStack(alignment: .top, spacing: 10) {
                            ToolIcon(tool: tool, size: 14)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(tool.title).font(.system(size: 12, weight: .medium))
                                    KeyCap(String(tool.shortcut.character).uppercased())
                                }
                                Text(tool.help)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var keySection: some View {
        let rows = Self.keys.filter { hit("\($0.0) \($0.1)") }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeading("Keys")
                    ForEach(rows, id: \.0) { key, what in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            KeyCap(key)
                                .frame(width: 92, alignment: .leading)
                            Text(what).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var recipeSection: some View {
        let rows = Self.recipes.filter { hit("\($0.title) \($0.body)") }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading("How do I…")
                    ForEach(rows, id: \.title) { recipe in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.title).font(.system(size: 12, weight: .medium))
                            Text(recipe.body)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Search

    private func hit(_ haystack: String) -> Bool {
        query.isEmpty || haystack.localizedCaseInsensitiveContains(query)
    }

    private var isEmptyResult: Bool {
        guard !query.isEmpty else { return false }
        return !hit(Self.intro)
            && Tool.allCases.allSatisfy { !hit("\($0.title) \($0.help)") }
            && Self.keys.allSatisfy { !hit("\($0.0) \($0.1)") }
            && Self.recipes.allSatisfy { !hit("\($0.title) \($0.body)") }
    }

    // MARK: Content

    private static let intro = """
    Pick a tool on the left, a colour at the bottom: left-click paints with the foreground \
    colour, right-click with the background one. The options under the toolbox change with \
    the tool, and only ever show what that tool actually uses. ⌘Z undoes the last 32 steps.
    """

    private static let keys: [(String, String)] = [
        ("⌘N", "New picture"),
        ("⇧⌘N", "New picture with a transparent background"),
        ("⌘O / ⌘S", "Open · Save (⇧⌘S saves as)"),
        ("⌘Z / ⇧⌘Z", "Undo · Redo"),
        ("⌘X ⌘C ⌘V", "Cut, copy and paste — paste lands as a floating selection, and grows the canvas if it does not fit"),
        ("⇧⌘V", "New from Clipboard: the clipboard picture becomes the canvas, at its own size"),
        ("⌘A / ⌘D", "Select all · Deselect"),
        ("⌘R", "Canvas size"),
        ("⇧⌘K", "Crop to the selection"),
        ("⌘I", "Invert colours"),
        ("⌘⌫", "Clear the picture to the background colour"),
        ("⌘+ / ⌘−", "Zoom in · out (⌘1 actual size, ⌘0 fit in window)"),
        ("X", "Swap the foreground and background colours"),
        ("Arrows", "Nudge a floating selection one pixel; ⇧ nudges ten"),
        ("⌥-drag", "Duplicate a selection instead of moving it"),
        ("⇧-drag", "Constrain a line to 45°, a rectangle to a square, an ellipse to a circle"),
        ("⌫", "Delete the selected pixels"),
        ("Escape", "Drop a floating selection back where it came from, or cancel typing"),
        ("⏎", "Stamp the text you are typing into the picture"),
    ]

    private struct Recipe { let title: String; let body: String }

    private static let recipes: [Recipe] = [
        Recipe(title: "Annotate a screenshot",
               body: """
               Take the shot with ⌃⇧⌘4 — that copies it to the clipboard — then press ⇧⌘V \
               here (File ▸ New from Clipboard). The canvas becomes the screenshot, at its \
               exact size, scaled down on screen if it is bigger than the window. Draw on it \
               and save with ⌘S. Plain ⌘V is the other half of this: it drops the clipboard \
               picture into the picture you already have, growing the canvas if what you \
               pasted is bigger than it. One ⌘Z undoes the paste and the growth together.
               """),
        Recipe(title: "Save a PNG with a transparent background",
               body: """
               A picture that already has transparency keeps it, opened or pasted in with \
               ⇧⌘V — a window screenshot (⌃⇧⌘4 then Space) brings its see-through corners \
               with it. Otherwise start from File ▸ New with Transparent Background (⇧⌘N), or knock the \
               background out of a picture you already have: right-click the background with \
               the eyedropper so it lands in the background swatch, then Image ▸ Make \
               Background Colour Transparent. Raise Tolerance first if the edges are soft or \
               the picture came from a JPEG. The checkerboard shows what is see-through. Save \
               as PNG — JPEG has no transparency and flattens onto white.
               """),
        Recipe(title: "Swap one colour for another",
               body: """
               Take Replace Colour (G), set the colour you want in the foreground swatch, then \
               click any pixel of the colour you want gone: every pixel of it changes at once. \
               Right-click swaps to the background colour instead. Tolerance widens the match \
               for photographic or antialiased art, and soft edges stay soft — the pixel keeps \
               its own opacity and only its colour changes. Select an area first to limit the \
               swap to it; outside a selection the whole picture changes.
               """),
        Recipe(title: "Copy a patch of the picture over a blemish",
               body: """
               Clone Stamp (K): ⌥-click clean pixels to set the source, then paint over the \
               blemish. The source travels with your stroke at the offset you set, and it \
               copies the picture as it was when you pressed the button, so crossing your own \
               source cannot smear.
               """),
        Recipe(title: "Move or duplicate part of the picture",
               body: """
               Select (S), drag a rectangle, then drag inside it to move the pixels — the hole \
               fills with the background colour. Hold ⌥ while you start the drag to leave the \
               original in place and move a copy. Arrows nudge it; Escape puts it back; \
               clicking outside it or changing tool stamps it down.
               """),
        Recipe(title: "Get a crisp pixel instead of a soft one",
               body: """
               Pencil (P) is always hard-edged and one pixel wide — it ignores Smooth edges \
               entirely. Smooth edges only affects Brush, Clone Stamp and the four shape \
               tools, which is why turning it off looks like nothing happened with the pencil \
               selected. The difference is easiest to see on a diagonal at 400% or more.
               """),
        Recipe(title: "Work precisely",
               body: """
               ⌘+ zooms; the pixel grid appears from 800% and can be turned off in View. The \
               status bar shows the cursor position, the canvas size and the colour under the \
               pointer. ⌘R resizes the canvas or scales the picture into it.
               """),
    ]
}

private struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12)))
    }
}

/// A plain AppKit window rather than a second SwiftUI `Window` scene: the app owns the
/// reference, so closing the drawing can close the help with it and the red button still
/// quits instead of leaving a canvas-less app alive behind a help panel.
@MainActor
final class HelpWindow {
    static let shared = HelpWindow()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow],
                        backing: .buffered, defer: false)
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = false
        w.title = "Daub Help"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: HelpView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}
