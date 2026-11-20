import CoreGraphics
import SharedKit

/// Reads one pixel of `image` and returns it as 8-bit sRGB.
///
/// - Parameter p: image pixel coordinates with a top-left origin (fractions are floored).
/// - Returns: `nil` when `p` lies outside the image or the pixel cannot be read.
public func sampleColor(in image: CGImage, atPixel p: CGPoint) -> RGBColor? {
    let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
    guard x >= 0, y >= 0, x < image.width, y < image.height,
          let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
          let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

    var bytes = [UInt8](repeating: 0, count: 4)
    let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
        guard let ctx = CGContext(
            data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.interpolationQuality = .none
        // Drawing into an sRGB context converts (and clamps) wider gamuts such as Display P3.
        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    guard drawn else { return nil }

    let a = Int(bytes[3])
    guard a > 0 else { return RGBColor(r: 0, g: 0, b: 0) }
    func unpremultiply(_ v: UInt8) -> Int { a == 255 ? Int(v) : min(255, (Int(v) * 255 + a / 2) / a) }
    return RGBColor(r: unpremultiply(bytes[0]), g: unpremultiply(bytes[1]), b: unpremultiply(bytes[2]))
}
