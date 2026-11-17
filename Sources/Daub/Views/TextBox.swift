import AppKit

/// The text tool's editor, floating over the canvas until it is stamped in.
///
/// The text is laid out in canvas pixels and only *shown* magnified: `scaler` has view-sized
/// frame and pixel-sized bounds. That is what makes the box exactly what gets stamped —
/// the same layout manager breaks the lines on screen and in the bitmap, so a line cannot
/// wrap at a different word on the way in, at any zoom.
final class TextBoxView: NSView {
    /// View points around the text: the band you grab to move the box or drag its sides.
    static let band: CGFloat = 8
    /// Narrowest a box can be dragged, in canvas pixels.
    static let minimumWidth: CGFloat = 8

    /// Top-left corner of the text in canvas pixels (canvas y grows upward, so this is the
    /// top edge — the box grows downward from it as lines are added).
    private(set) var anchor: CGPoint
    /// nil: one line per paragraph, as long as you type, breaking only on Return.
    /// A width: the lines wrap at it, like a text box in a word processor.
    private(set) var wrapWidth: CGFloat?
    /// A dragged-out box keeps at least the height it was drawn with.
    private let minimumHeight: CGFloat
    private var zoom: CGFloat

    let textView: TextBoxTextView
    private let scaler = FlippedView()
    private let typingUndo = UndoManager()
    weak var canvas: CanvasView?

    private enum Grab { case move, left, right }
    private var grab: (kind: Grab, start: CGPoint, anchor: CGPoint, width: CGFloat)?

    init(anchor: CGPoint, wrapWidth: CGFloat?, minimumHeight: CGFloat, zoom: CGFloat,
         font: NSFont, colour: NSColor) {
        self.anchor = anchor
        self.wrapWidth = wrapWidth.map { max(Self.minimumWidth, $0) }
        self.minimumHeight = minimumHeight
        self.zoom = zoom

        // TextKit 1 on purpose: `drawGlyphs(forGlyphRange:at:)` is what stamps the text, and
        // it has to be the very layout the user was looking at.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: self.wrapWidth ?? .greatestFiniteMagnitude,
                                                     height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        textView = TextBoxTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)

        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.usesFontPanel = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.insertionPointColor = .controlAccentColor
        textView.typingAttributes = [.font: font, .foregroundColor: colour]
        textView.delegate = self

        scaler.addSubview(textView)
        addSubview(scaler)
        relayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var string: String { textView.string }
    /// Nothing that would put a pixel down: empty, or only spaces and line breaks.
    var isBlank: Bool { textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canUndoTyping: Bool { typingUndo.canUndo }
    var canRedoTyping: Bool { typingUndo.canRedo }
    func undoTyping() { typingUndo.undo() }
    func redoTyping() { typingUndo.redo() }

    /// The text area (not the band) in canvas pixels.
    var textRect: CGRect {
        let size = textView.frame.size
        return CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
    }

    func setZoom(_ zoom: CGFloat) {
        guard zoom != self.zoom else { return }
        self.zoom = zoom
        relayout()
    }

    // MARK: - Layout

    /// Size the text view to what it holds and the box to the text view, keeping the top-left
    /// corner where it is.
    func relayout() {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        container.size = CGSize(width: wrapWidth ?? .greatestFiniteMagnitude,
                                height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        // A free line is as wide as its text plus room for the caret; a wrapping box is as
        // wide as the user made it.
        let width = wrapWidth ?? max(ceil(used.maxX) + 2, 4)
        let height = max(ceil(used.maxY), minimumHeight, 4)
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let band = Self.band
        scaler.frame = CGRect(x: band, y: band, width: width * zoom, height: height * zoom)
        scaler.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let old = frame
        frame = CGRect(x: anchor.x * zoom - band, y: (anchor.y - height) * zoom - band,
                       width: width * zoom + band * 2, height: height * zoom + band * 2)
        if old != frame {
            superview?.setNeedsDisplay(old.union(frame))
            window?.invalidateCursorRects(for: self)
        }
        needsDisplay = true
    }

    // MARK: - Style

    /// Font family, size or colour picked while typing. With text selected it applies to the
    /// selection; with nothing selected, to everything in the box — the change is visible at
    /// once either way. What is typed next takes it too.
    func apply(fontName: String?, fontSize: CGFloat?, colour: NSColor?) {
        guard fontName != nil || fontSize != nil || colour != nil,
              let storage = textView.textStorage else { return }
        let selected = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let ranges = selected.isEmpty ? [NSRange(location: 0, length: storage.length)] : selected

        func restyled(_ font: NSFont) -> NSFont {
            let size = fontSize ?? font.pointSize
            if let fontName { return NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size) }
            return NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        }

        let changing = ranges.filter { $0.length > 0 }
        if !changing.isEmpty,
           textView.shouldChangeText(inRanges: changing.map { NSValue(range: $0) }, replacementStrings: nil) {
            storage.beginEditing()
            for range in changing {
                if let colour { storage.addAttribute(.foregroundColor, value: colour, range: range) }
                if fontName != nil || fontSize != nil {
                    storage.enumerateAttribute(.font, in: range) { value, run, _ in
                        let font = value as? NSFont ?? .systemFont(ofSize: fontSize ?? 12)
                        storage.addAttribute(.font, value: restyled(font), range: run)
                    }
                }
            }
            storage.endEditing()
            textView.didChangeText()
        }

        var typing = textView.typingAttributes
        if let colour { typing[.foregroundColor] = colour }
        if fontName != nil || fontSize != nil {
            typing[.font] = restyled(typing[.font] as? NSFont ?? .systemFont(ofSize: fontSize ?? 12))
        }
        textView.typingAttributes = typing
        relayout()
    }

    // MARK: - Stamping

    /// Every pixel the glyphs reach, in canvas pixels — found by stamping them into a
    /// scratch mask, not by asking the font. Stacked combining marks and swashes paint far
    /// outside the line box and outside what the metrics admit, and a rectangle that is too
    /// small here is text that Undo cannot fully remove. Ink that reaches the mask's edge
    /// returns nil: the caller must then capture the whole canvas.
    func coveredRect() -> CGRect? {
        var largest: CGFloat = 0
        if let storage = textView.textStorage {
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                largest = max(largest, (value as? NSFont)?.pointSize ?? 0)
            }
        }
        let margin = ceil(max(64, largest * 6))
        let text = textRect.integral
        let width = Int(text.width + margin * 2), height = Int(text.height + margin * 2)
        guard width > 0, height > 0, width * height <= 64_000_000,
              let mask = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let bytes = mask.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        mask.translateBy(x: margin - text.minX, y: margin - text.minY)
        render(into: mask, inkOnly: true)

        // Rows in the buffer run top-down; canvas y runs bottom-up.
        var minX = Int.max, minRow = Int.max, maxX = -1, maxRow = -1
        for row in 0..<height {
            let line = bytes + row * width
            for x in 0..<width where line[x] != 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        if maxX < 0 { return text }
        if minX == 0 || minRow == 0 || maxX == width - 1 || maxRow == height - 1 { return nil }
        let ink = CGRect(x: text.minX - margin + CGFloat(minX),
                         y: text.minY - margin + CGFloat(height - 1 - maxRow),
                         width: CGFloat(maxX - minX + 1), height: CGFloat(maxRow - minRow + 1))
        return text.union(ink).insetBy(dx: -2, dy: -2)
    }

    /// Draw the text into a bottom-up canvas context exactly as the box lays it out.
    func render(into ctx: CGContext, inkOnly: Bool = false) {
        guard let layout = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage else { return }
        let glyphs = layout.glyphRange(for: container)
        // Measuring: every glyph white on the black mask, whatever its own colour.
        let colours = inkOnly ? storage.attributes(forColour: .white) : nil
        defer { if let colours { storage.restore(colours) } }
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// Fold any half-composed input (a dead key, an input method) into the text.
    func finishComposing() {
        if textView.hasMarkedText() { textView.unmarkText() }
    }

    // MARK: - The band: move and resize

    private func grabKind(at p: CGPoint) -> Grab {
        if p.x < Self.band + 2 { return .left }
        if p.x > bounds.width - Self.band - 2 { return .right }
        return .move
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        grab = (grabKind(at: p), event.locationInWindow, anchor, textView.frame.width)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab else { return }
        let dx = (event.locationInWindow.x - grab.start.x) / zoom
        let dy = (event.locationInWindow.y - grab.start.y) / zoom
        switch grab.kind {
        case .move:
            anchor = CGPoint(x: (grab.anchor.x + dx).rounded(), y: (grab.anchor.y + dy).rounded())
        case .right:
            wrapWidth = max(Self.minimumWidth, (grab.width + dx).rounded())
        case .left:
            let width = max(Self.minimumWidth, (grab.width - dx).rounded())
            anchor.x = grab.anchor.x + grab.width - width
            wrapWidth = width
        }
        relayout()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        grab = nil
        window?.makeFirstResponder(textView)
    }

    override func resetCursorRects() {
        let band = Self.band + 2
        addCursorRect(bounds, cursor: .openHand)
        addCursorRect(CGRect(x: 0, y: 0, width: band, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: bounds.width - band, y: 0, width: band, height: bounds.height),
                      cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = scaler.frame.insetBy(dx: -1.5, dy: -1.5)
        let path = NSBezierPath(rect: outline)
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.stroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
        // Side handles: the box's width is the thing worth adjusting.
        for x in [outline.minX, outline.maxX] {
            let handle = NSBezierPath(rect: CGRect(x: x - 3, y: outline.midY - 3, width: 6, height: 6))
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }
    }
}

extension TextBoxView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        relayout()
        canvas?.textBoxDidChange()
    }

    /// The box keeps its own typing history, so ⌘Z while typing takes back typing and not
    /// the stroke before it.
    func undoManager(for view: NSTextView) -> UndoManager? { typingUndo }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            canvas?.cancelText()
            return true
        }
        return false
    }
}

/// The text view inside the box. Return makes a new line; ⌘Return stamps the text.
final class TextBoxTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.contains(.command),
           event.keyCode == 36 || event.keyCode == 76 {
            (superview?.superview as? TextBoxView)?.canvas?.commitText()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// The colour panel sends its colour down the responder chain, and the text view would
    /// colour the selection itself, behind the editor's back. The swatch binding already
    /// carries the change to the box, so this path stays quiet.
    override func changeColor(_ sender: Any?) {}

    /// Pasted text takes the box's style, not the font and colour of wherever it came from.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

private extension NSTextStorage {
    /// Swap every run's colour for one, handing back what to restore.
    func attributes(forColour colour: NSColor) -> [(NSRange, Any?)] {
        var saved: [(NSRange, Any?)] = []
        let all = NSRange(location: 0, length: length)
        enumerateAttribute(.foregroundColor, in: all) { value, range, _ in saved.append((range, value)) }
        beginEditing()
        addAttribute(.foregroundColor, value: colour, range: all)
        endEditing()
        return saved
    }

    func restore(_ saved: [(NSRange, Any?)]) {
        beginEditing()
        for (range, value) in saved {
            if let value { addAttribute(.foregroundColor, value: value, range: range) }
            else { removeAttribute(.foregroundColor, range: range) }
        }
        endEditing()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
