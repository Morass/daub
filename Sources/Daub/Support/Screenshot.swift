import AppKit
import SwiftUI

/// Self-capture, for the picture in the README.
///
/// The app draws its own window into a bitmap — no screen recording, no window-server
/// capture, nothing that needs a permission dialog on somebody's desk. That matters here
/// because the machine that builds the README has no one sitting at it.
///
///     DAUB_SCREENSHOT=/tmp/shot.png DAUB_SCREENSHOT_ART=Resources/readme-art.png \
///         build/Daub.app/Contents/MacOS/Daub
///
/// Exits when it is done. `make screenshot` wraps it.
@MainActor
enum Screenshot {
    /// True while the app is rendering itself for the README, so views that cannot be
    /// captured offscreen can present the same thing in a capturable way.
    static let isCapturing = ProcessInfo.processInfo.environment["DAUB_SCREENSHOT"] != nil

    static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["DAUB_SCREENSHOT"] else { return }
        let art = env["DAUB_SCREENSHOT_ART"].map { URL(fileURLWithPath: $0) }

        // Two hops through the run loop: the first lets SwiftUI build the chrome and gives
        // the canvas a document to show, the second lets that document finish drawing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let editor = Editor.current
            if let art { editor?.open(art) }
            editor?.tool = .brush
            editor?.primary = Color(red: 0.89, green: 0.29, blue: 0.25)
            editor?.secondary = Color(red: 1, green: 1, blue: 1)
            resizeWindow()
            editor?.zoomToFit()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                capture(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    private static func resizeWindow() {
        guard let window = canvasWindow() else { return }
        // NSToolbar items are not part of the layer tree we can render, and come out as a
        // white slab. Better an honest plain title bar than a blank shape where four
        // buttons should be.
        window.toolbar?.isVisible = false
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        window.setFrame(frame, display: true)
        window.center()
    }

    private static func capture(to url: URL) {
        guard let window = canvasWindow(),
              // The theme frame, not the content view: that is what carries the title bar.
              let root = window.contentView?.superview ?? window.contentView
        else { return note("no window") }

        let scale = window.backingScaleFactor
        let size = root.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return note("no bitmap") }

        rep.size = size
        // Render the LAYER tree, not the view tree: SwiftUI draws into layers, and
        // `cacheDisplay` walks views — it comes back with an empty sidebar and a blank
        // toolbar. `CALayer.render(in:)` walks what is actually on screen.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        if let layer = root.layer {
            layer.render(in: ctx.cgContext)
        } else {
            root.cacheDisplay(in: root.bounds, to: rep)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return note("no png") }
        try? data.write(to: url)
        note("wrote \(url.path)")
    }

    private static func note(_ message: String) {
        FileHandle.standardError.write(Data("screenshot: \(message)\n".utf8))
    }

    private static func canvasWindow() -> NSWindow? {
        NSApp.windows.first { $0.contentView != nil && !($0 is NSPanel) }
    }
}
