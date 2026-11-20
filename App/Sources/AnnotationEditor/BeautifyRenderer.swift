import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import SwiftUI

enum BeautifyRenderer {
    struct Output {
        let image: CGImage
        /// Set when the chosen background could not be used and a fallback
        /// was drawn instead. Callers show it to the user.
        let warning: String?
    }

    static let missingBackgroundImageWarning = String(
        localized: "Background image could not be loaded, a solid color was used instead"
    )

    static func render(image: CGImage, settings: BeautifySettings) -> Output? {
        guard settings.isEnabled else { return Output(image: image, warning: nil) }

        let cornerRadius = max(0, settings.cornerRadius)
        let shadowRadius = settings.clampedShadowRadius
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvas = settings.canvasSize(for: imageSize)
        let outputWidth = Int(canvas.width)
        let outputHeight = Int(canvas.height)
        var warning: String?

        guard outputWidth > 0, outputHeight > 0, let ctx = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvasRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

        switch settings.backgroundStyle {
        case .solid:
            fillSolid(ctx, canvasRect, settings)

        case .gradient(let gradient):
            BeautifyGradients.draw(gradient, in: ctx, rect: canvasRect)

        case .image(let url):
            if let picture = loadImage(at: url) {
                ctx.saveGState()
                ctx.clip(to: canvasRect)
                ctx.draw(picture, in: aspectFillRect(for: CGSize(width: picture.width, height: picture.height), in: canvasRect))
                ctx.restoreGState()
            } else {
                fillSolid(ctx, canvasRect, settings)
                warning = missingBackgroundImageWarning
            }

        case .liquidGlass:
            // Fall back to a dark fill if CI fails for any reason.
            ctx.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 1).cgColor)
            ctx.fill(canvasRect)

            if let backdrop = liquidGlassBackdrop(from: image, targetSize: canvasRect.size) {
                // CGContext.draw(_:in:) renders CGImages right-side-up in a
                // bottom-left CGBitmapContext — no y-flip required. Same as
                // AnnotationRenderer does with the source image.
                ctx.draw(backdrop, in: canvasRect)
            }

            // Subtle white sheen so the glass feels slightly brightened.
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.03).cgColor)
            ctx.fill(canvasRect)

        case .none:
            break
        }

        let insets = settings.canvasInsets(for: imageSize)
        let imageRect = CGRect(
            x: insets.horizontal.rounded(.down),
            y: insets.vertical.rounded(.down),
            width: imageSize.width,
            height: imageSize.height
        )

        // The shadow is cast by the clipped image itself, so it follows the
        // screenshot's own transparent corners instead of a filled shape
        // that can show through them.
        ctx.saveGState()
        if settings.shadowEnabled {
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: shadowRadius, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(Path(roundedRect: imageRect, cornerRadius: cornerRadius, style: .continuous).cgPath)
        ctx.clip()
        // No y-flip: CGContext.draw(_:in:) already renders CGImages right-side-up
        // in a bottom-left CGBitmapContext. (AnnotationRenderer does the same.)
        ctx.draw(image, in: imageRect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        guard let output = ctx.makeImage() else { return nil }
        return Output(image: output, warning: warning)
    }

    private static func fillSolid(_ ctx: CGContext, _ rect: CGRect, _ settings: BeautifySettings) {
        ctx.setFillColor(NSColor(settings.backgroundColor).cgColor)
        ctx.fill(rect)
    }

    /// Reads a user-chosen background picture, upright (EXIF orientation
    /// applied) and at most `maxPixelSize` on its long side; nil when missing
    /// or unreadable.
    static func loadImage(at url: URL, maxPixelSize: Int = 8192) -> CGImage? {
        guard url.isFileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The rect that covers `bounds` completely with `size`'s aspect, centred.
    static func aspectFillRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    /// Build a "liquid glass" backdrop: an aspect-fill copy of the source
    /// image, saturation-boosted and heavily Gaussian-blurred, rendered to
    /// exactly `targetSize`. The resulting image extends the screenshot's own
    /// colours into the padding area around the final output.
    private static func liquidGlassBackdrop(from image: CGImage, targetSize: CGSize) -> CGImage? {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        guard srcW > 0, srcH > 0, targetSize.width > 0, targetSize.height > 0 else { return nil }

        // Aspect-fill scale, with a slight overshoot so the blur never reveals
        // hard edges inside the canvas.
        let coverScale = max(targetSize.width / srcW, targetSize.height / srcH)
        let scale = coverScale * 1.15

        var ci = CIImage(cgImage: image)
        ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Centre the scaled image on the target canvas.
        let tx = (targetSize.width - ci.extent.width) / 2 - ci.extent.minX
        let ty = (targetSize.height - ci.extent.height) / 2 - ci.extent.minY
        ci = ci.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Boost saturation for a richer, glass-like colour bloom.
        if let f = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ci,
            kCIInputSaturationKey: 1.9,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 0.95,
        ]), let out = f.outputImage {
            ci = out
        }

        // Clamp before blurring so edges don't fade to transparent/black.
        let clamped = ci.clampedToExtent()
        if let f = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: 120.0,
        ]), let out = f.outputImage {
            ci = out
        }

        let context = CIContext(options: nil)
        let target = CGRect(origin: .zero, size: targetSize)
        return context.createCGImage(ci, from: target)
    }
}
