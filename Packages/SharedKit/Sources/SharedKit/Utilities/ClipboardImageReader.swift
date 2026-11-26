import AppKit
import CoreGraphics
import ImageIO

/// Reads an image from the clipboard for editing. Images beyond the limits of
/// `ClipboardPinContentReader.isSafeImageDimensions` are refused before decoding,
/// so a crafted or huge clipboard image can't exhaust memory.
public enum ClipboardImageReader {
    public static func image(from pasteboard: NSPasteboard = .general) -> CGImage? {
        fileURLImage(from: pasteboard)
            ?? objectImage(from: pasteboard)
            ?? dataImage(from: pasteboard)
    }

    private static func fileURLImage(from pasteboard: NSPasteboard) -> CGImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        guard let url = urls?.first(where: { $0.isFileURL }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              hasSafeDimensions(source) else {
            return nil
        }
        return ImageFileReader.image(at: url)
    }

    private static func objectImage(from pasteboard: NSPasteboard) -> CGImage? {
        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        guard let image = images?.first, hasSafeDimensions(image) else { return nil }
        return ImageUtilities.cgImage(from: image)
    }

    private static func dataImage(from pasteboard: NSPasteboard) -> CGImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  hasSafeDimensions(source),
                  let image = NSImage(data: data),
                  let cgImage = ImageUtilities.cgImage(from: image) else {
                continue
            }
            return cgImage
        }
        return nil
    }

    /// Reads only the header (pixel size), not the image data.
    private static func hasSafeDimensions(_ source: CGImageSource) -> Bool {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return false
        }
        return ClipboardPinContentReader.isSafeImageDimensions(width: width, height: height)
    }

    /// Largest representation (bitmap pixels, or point size for vector reps).
    private static func hasSafeDimensions(_ image: NSImage) -> Bool {
        let width = image.representations.map { max($0.pixelsWide, Int($0.size.width.rounded(.up))) }.max()
            ?? Int(image.size.width.rounded(.up))
        let height = image.representations.map { max($0.pixelsHigh, Int($0.size.height.rounded(.up))) }.max()
            ?? Int(image.size.height.rounded(.up))
        return ClipboardPinContentReader.isSafeImageDimensions(width: width, height: height)
    }
}
