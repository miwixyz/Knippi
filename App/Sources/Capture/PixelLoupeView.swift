// App/Sources/Capture/PixelLoupeView.swift
import AppKit
import CaptureKit
import SharedKit

/// Draws the colour-picker pixel loupe into the capture overlay's context.
/// Not a separate view or window: the overlay calls `draw` from `draw(_:)`
/// so the loupe moves in the same frame as the reticle.
@MainActor
enum PixelLoupeView {
    private static let side = PixelLoupeGeometry.pixelsPerSide
    private static let zoom = PixelLoupeGeometry.magnification
    private static let labelHeight: CGFloat = 24
    private static let cornerRadius: CGFloat = 10
    private static let labelFont = NSFont.safeMonospacedSystemFont(ofSize: 11, weight: .medium)

    private static var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: labelFont, .foregroundColor: NSColor.white]
    }

    /// Loupe size; wider than the pixel grid only when the label needs it.
    static func size(forLabel label: String?) -> CGSize {
        let loupe = CGFloat(side) * zoom
        let textWidth = label.map { ($0 as NSString).size(withAttributes: labelAttributes).width } ?? 0
        let labelWidth = 8 + 12 + 6 + textWidth.rounded(.up) + 8
        return CGSize(width: max(loupe, labelWidth), height: loupe + labelHeight)
    }

    /// - Parameters:
    ///   - image: the frozen display image (backing pixels, top-left origin).
    ///   - centerPixel: image pixel under the sample point.
    ///   - cursor: sample point in view coordinates; the loupe is offset from it.
    ///   - label: colour text shown below the pixels (nil hides the colour row content).
    static func draw(
        image: CGImage,
        centerPixel: CGPoint,
        cursor: CGPoint,
        bounds: CGRect,
        color: SharedKit.RGBColor?,
        label: String?,
        in context: CGContext
    ) {
        let total = size(forLabel: label)
        let origin = PixelLoupeGeometry.loupeOrigin(cursor: cursor, loupeSize: total, bounds: bounds)
        let frame = CGRect(origin: origin, size: total)
        let loupeSide = CGFloat(side) * zoom
        let pixelRect = CGRect(x: frame.midX - loupeSide / 2, y: frame.maxY - loupeSide, width: loupeSide, height: loupeSide)
        let framePath = CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        context.saveGState()
        // Soft shadow so the loupe separates from any background.
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 12, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.addPath(framePath)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(framePath)
        context.clip()

        // Magnified pixels, nearest-neighbour.
        let half = side / 2
        let cx = Int(centerPixel.x), cy = Int(centerPixel.y)
        let wanted = CGRect(x: cx - half, y: cy - half, width: side, height: side)
        let available = wanted.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if !available.isNull, !available.isEmpty, let crop = image.cropping(to: available) {
            let dx = (available.minX - wanted.minX) * zoom
            let dyTop = (available.minY - wanted.minY) * zoom
            let dest = CGRect(
                x: pixelRect.minX + dx,
                y: pixelRect.maxY - dyTop - available.height * zoom,
                width: available.width * zoom,
                height: available.height * zoom
            )
            context.interpolationQuality = .none
            context.draw(crop, in: dest)
        }

        // 1-pt grid.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        context.setLineWidth(1)
        for i in 1..<side {
            let offset = CGFloat(i) * zoom
            context.move(to: CGPoint(x: pixelRect.minX + offset, y: pixelRect.minY))
            context.addLine(to: CGPoint(x: pixelRect.minX + offset, y: pixelRect.maxY))
            context.move(to: CGPoint(x: pixelRect.minX, y: pixelRect.minY + offset))
            context.addLine(to: CGPoint(x: pixelRect.maxX, y: pixelRect.minY + offset))
        }
        context.strokePath()

        // Centre pixel: black outer, white inner outline.
        let centre = CGRect(
            x: pixelRect.minX + CGFloat(half) * zoom,
            y: pixelRect.minY + CGFloat(half) * zoom,
            width: zoom,
            height: zoom
        )
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.stroke(centre.insetBy(dx: -1, dy: -1))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(centre)

        // Label bar.
        let bar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: labelHeight)
        context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.fill(bar)
        context.restoreGState()

        var textX = bar.minX + 8
        if let color {
            let swatch = CGRect(x: textX, y: bar.midY - 6, width: 12, height: 12)
            context.setFillColor(NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                                         blue: CGFloat(color.b) / 255, alpha: 1).cgColor)
            context.fill(swatch)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1)
            context.stroke(swatch.insetBy(dx: 0.5, dy: 0.5))
            textX = swatch.maxX + 6
        }
        if let label {
            let text = label as NSString
            let textSize = text.size(withAttributes: labelAttributes)
            text.draw(at: CGPoint(x: textX, y: bar.midY - textSize.height / 2), withAttributes: labelAttributes)
        }

        // Thin border on top for definition.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: cornerRadius,
                               cornerHeight: cornerRadius, transform: nil))
        context.strokePath()
    }
}
