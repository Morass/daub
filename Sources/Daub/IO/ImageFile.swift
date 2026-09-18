import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Reading and writing pixels, straight through ImageIO — no NSImage round-trip, which
/// would silently resample and colour-manage behind our back.
enum ImageFile {
    struct Failure: LocalizedError {
        let what: String
        var errorDescription: String? { what }
    }

    static let readableTypes: [UTType] = [.png, .jpeg, .tiff, .bmp, .gif, .heic, .webP]
    static let writableTypes: [UTType] = [.png, .jpeg, .tiff]

    static func canWrite(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return writableTypes.contains { type.conforms(to: $0) }
    }

    static func read(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: true,
              ] as CFDictionary)
        else {
            throw Failure(what: "“\(url.lastPathComponent)” is not an image Daub can read.")
        }
        return image
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        let type: UTType = switch ext {
        case "jpg", "jpeg": .jpeg
        case "tif", "tiff": .tiff
        default: .png
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(what: "Could not create “\(url.lastPathComponent)”.")
        }
        var options: [CFString: Any] = [:]
        if type == .jpeg { options[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw Failure(what: "Could not write “\(url.lastPathComponent)”.")
        }
    }

    // MARK: - Pasteboard

    /// - Parameter pb: the board to read. Defaults to the system clipboard; the built-in
    ///   self-test passes a private one so running it cannot clobber what the user copied.
    static func readFromPasteboard(_ pb: NSPasteboard = .general) -> CGImage? {
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first {
            return try? read(url)
        }
        return nil
    }

    static func writeToPasteboard(_ image: CGImage, to pb: NSPasteboard = .general) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        pb.clearContents()
        pb.setData(data, forType: .png)
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }
}
