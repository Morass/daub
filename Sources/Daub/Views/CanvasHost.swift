import AppKit
import SwiftUI

/// Holds the canvas centred in the scroll view and paints the workbench around it.
final class CanvasContainerView: NSView {
    let canvasView: CanvasView

    init(canvasView: CanvasView) {
        self.canvasView = canvasView
        super.init(frame: .zero)
        addSubview(canvasView)
        postsFrameChangedNotifications = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { true }

    private let margin: CGFloat = 32

    func refreshLayout() {
        let canvas = canvasView.scaledSize
        let visible = enclosingScrollView?.contentView.bounds.size ?? canvas
        let width = max(canvas.width + margin * 2, visible.width)
        let height = max(canvas.height + margin * 2, visible.height)
        if frame.size != CGSize(width: width, height: height) {
            setFrameSize(CGSize(width: width, height: height))
        }
        canvasView.setFrameOrigin(CGPoint(x: ((width - canvas.width) / 2).rounded(),
                                          y: ((height - canvas.height) / 2).rounded()))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.underPageBackgroundColor.cgColor)
        ctx.fill(dirtyRect)

        // A hairline and a soft drop shadow are the whole difference between "a bitmap
        // in a window" and "a sheet of paper on a desk".
        let frame = canvasView.frame
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 8,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(frame)
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(frame.insetBy(dx: -0.5, dy: -0.5))
    }
}

final class CloseGuard: NSObject, NSWindowDelegate {
    weak var next: NSWindowDelegate?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Editor.current?.confirmDiscardIfNeeded() ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(windowShouldClose(_:)) { return true }
        return super.responds(to: selector) || (next?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? { next }
}

struct CanvasHost: NSViewRepresentable {
    @ObservedObject var editor: Editor

    func makeNSView(context: Context) -> NSScrollView {
        let canvas = CanvasView(editor: editor)
        let container = CanvasContainerView(canvasView: canvas)

        let scroll = NSScrollView()
        scroll.documentView = container
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.allowsMagnification = false
        scroll.contentView.postsBoundsChangedNotifications = true

        editor.canvas = canvas
        canvas.applyZoom()
        container.refreshLayout()

        context.coordinator.observe(scroll: scroll, container: container)
        DispatchQueue.main.async {
            canvas.window?.makeFirstResponder(canvas)
            context.coordinator.guardWindow(canvas.window)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let container = scroll.documentView as? CanvasContainerView else { return }
        if container.canvasView.frame.size != container.canvasView.scaledSize {
            container.canvasView.applyZoom()
        }
        container.refreshLayout()
        container.canvasView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSObjectProtocol?
        private let closeGuard = CloseGuard()

        /// Insert ourselves in front of SwiftUI's window delegate so the red close button
        /// asks about unsaved work. Everything we do not implement is forwarded straight
        /// back to SwiftUI, which still owns the window.
        func guardWindow(_ window: NSWindow?) {
            guard let window, !(window.delegate is CloseGuard) else { return }
            closeGuard.next = window.delegate
            window.delegate = closeGuard
        }

        func observe(scroll: NSScrollView, container: CanvasContainerView) {
            scroll.contentView.postsFrameChangedNotifications = true
            token = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scroll.contentView, queue: .main
            ) { [weak container] _ in
                MainActor.assumeIsolated { container?.refreshLayout() }
            }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}
