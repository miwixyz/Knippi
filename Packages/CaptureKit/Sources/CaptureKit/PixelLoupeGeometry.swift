import CoreGraphics

/// Placement and coordinate mapping for the colour-picker pixel loupe.
/// View coordinates are AppKit (bottom-left origin); image pixels are top-left.
public enum PixelLoupeGeometry {
    /// Number of image pixels shown per side.
    public static let pixelsPerSide = 11
    /// On-screen points per magnified image pixel.
    public static let magnification: CGFloat = 12
    /// Distance between cursor and loupe.
    public static let cursorOffset: CGFloat = 24

    /// Bottom-left origin of the loupe: below-right of the cursor, flipped
    /// to the other side when it would leave `bounds`.
    public static func loupeOrigin(
        cursor: CGPoint,
        loupeSize: CGSize,
        bounds: CGRect,
        offset: CGFloat = cursorOffset
    ) -> CGPoint {
        var x = cursor.x + offset
        if x + loupeSize.width > bounds.maxX { x = cursor.x - offset - loupeSize.width }
        var y = cursor.y - offset - loupeSize.height
        if y < bounds.minY { y = cursor.y + offset }
        return CGPoint(x: x, y: y)
    }

    /// The image pixel (top-left origin, clamped to the image) under a view point.
    public static func imagePixel(forViewPoint point: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width >= 1, imageSize.height >= 1 else {
            return .zero
        }
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        let px = (point.x * sx).rounded(.down)
        let py = ((viewSize.height - point.y) * sy).rounded(.down)
        return CGPoint(
            x: min(max(px, 0), imageSize.width - 1),
            y: min(max(py, 0), imageSize.height - 1)
        )
    }
}
