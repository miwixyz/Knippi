import Foundation
import CoreGraphics
import CoreImage

public final class PixelateObject: AnnotationObject, @unchecked Sendable {
    public let id = ObjectID()
    public var style: StrokeStyle
    public var rect: CGRect
    public var blockSize: CGFloat = 12
    public var mode: RedactionMode
    /// Set for redactions of confidential text ("Vertrauliches finden"): every block gets a
    /// fixed random brightness offset from this seed. Plain block averages still let someone
    /// who knows the font rule out candidates (measured 21.11.: one changed IBAN digit moved a
    /// block by 12 levels); an offset larger than that makes comparing against candidates
    /// useless. Fixed per object so the picture doesn't flicker between renders.
    public var noiseSeed: UInt64?

    /// Brightness offset range per block, in 8-bit levels (± this value).
    static let noiseAmplitude = 40

    public init(rect: CGRect, blockSize: CGFloat = 12, mode: RedactionMode = .pixelate, noiseSeed: UInt64? = nil) {
        self.rect = rect
        self.style = StrokeStyle()
        self.blockSize = blockSize
        self.mode = mode
        self.noiseSeed = noiseSeed
    }

    public var bounds: CGRect { rect }

    public func hitTest(point: CGPoint, threshold: CGFloat) -> Bool {
        rect.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }

    public func render(in ctx: CGContext) {
        ctx.saveGState()
        switch mode {
        case .solid:
            // Schwärzen ist ein Sicherheitswerkzeug: immer deckend schwarz.
            ctx.setAlpha(1)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(rect)
        case .pixelate, .blur:
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.3))
            ctx.fill(rect)
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.2))
            ctx.setLineWidth(0.5)
            var x = rect.minX
            while x <= rect.maxX {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += blockSize
            }
            var y = rect.minY
            while y <= rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += blockSize
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Nur für Tests: ersetzt den Filter, um Fehlerpfade zu prüfen.
    /// Nur beim App-Start bzw. serialisiert im Test setzen.
    nonisolated(unsafe) static var redactorOverride: ((CGImage, CGFloat, RedactionMode) -> CGImage?)?

    /// Wird aufgerufen, wenn der Filter scheitert; die App zeigt dann einen Hinweis.
    /// Nur beim App-Start bzw. serialisiert im Test setzen.
    nonisolated(unsafe) public static var reportFailure: (@Sendable () -> Void)?

    /// Apply the selected redaction filter on the source image region.
    /// `rect` is in image coordinates (top-left origin, matching source image pixel dimensions).
    /// The CGContext is assumed to be in a flipped coordinate system (isFlipped NSView).
    public func renderWithSource(in ctx: CGContext, sourceImage: CGImage) {
        guard rect.width > 0, rect.height > 0 else { return }

        if mode == .solid {
            render(in: ctx)
            return
        }

        // Redaction bounds already use source-image pixel coordinates with a top-left origin.
        let cropRect = rect.intersection(CGRect(
            x: 0,
            y: 0,
            width: CGFloat(sourceImage.width),
            height: CGFloat(sourceImage.height)
        ))
        guard !cropRect.isEmpty else { return }

        let redactor: (CGImage, CGFloat, RedactionMode) -> CGImage? =
            Self.redactorOverride ?? { [noiseSeed] in
                Self.makeRedactedImage(from: $0, blockSize: $1, mode: $2, noiseSeed: noiseSeed)
            }
        guard let cropped = sourceImage.cropping(to: cropRect),
              let redacted = redactor(cropped, blockSize, mode)
        else {
            // Fail closed: lieber schwarz als Klartext.
            ctx.saveGState()
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(cropRect)
            ctx.restoreGState()
            Self.reportFailure?()
            return
        }

        draw(redacted, in: cropRect, context: ctx)
    }

    private static func makeRedactedImage(
        from image: CGImage,
        blockSize: CGFloat,
        mode: RedactionMode,
        noiseSeed: UInt64? = nil
    ) -> CGImage? {
        switch mode {
        case .pixelate:
            makePixelatedImage(from: image, blockSize: blockSize, noiseSeed: noiseSeed)
        case .blur:
            // Pixelating first leaves only block averages, so the blur can't be undone to reveal text.
            makePixelatedImage(from: image, blockSize: blockSize, noiseSeed: noiseSeed)
                .flatMap { makeBlurredImage(from: $0, radius: max(4, blockSize * 0.9)) }
        case .solid:
            nil
        }
    }

    private func draw(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.interpolationQuality = mode == .pixelate ? .none : .high
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func makePixelatedImage(from image: CGImage, blockSize: CGFloat, noiseSeed: UInt64? = nil) -> CGImage? {
        let block = max(4, Int(blockSize.rounded()))
        let tinyWidth = max(1, image.width / block)
        let tinyHeight = max(1, image.height / block)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let downsampledContext = CGContext(
            data: nil,
            width: tinyWidth,
            height: tinyHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        downsampledContext.interpolationQuality = .low
        downsampledContext.draw(image, in: CGRect(x: 0, y: 0, width: tinyWidth, height: tinyHeight))
        guard let downsampled = downsampledContext.makeImage() else { return nil }

        let chunkyWidth = max(1, tinyWidth / 2)
        let chunkyHeight = max(1, tinyHeight / 2)
        guard let chunkyContext = CGContext(
            data: nil,
            width: chunkyWidth,
            height: chunkyHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        chunkyContext.interpolationQuality = .low
        chunkyContext.draw(downsampled, in: CGRect(x: 0, y: 0, width: chunkyWidth, height: chunkyHeight))
        if let noiseSeed {
            // Fail closed: without access to the block pixels the noise can't be applied.
            guard let data = chunkyContext.data else { return nil }
            addBlockNoise(
                to: data.assumingMemoryBound(to: UInt8.self),
                width: chunkyWidth, height: chunkyHeight,
                bytesPerRow: chunkyContext.bytesPerRow, seed: noiseSeed
            )
        }
        guard let chunky = chunkyContext.makeImage() else { return nil }

        guard let outputContext = CGContext(
            data: nil,
            width: max(1, image.width),
            height: max(1, image.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        outputContext.interpolationQuality = .none
        outputContext.draw(chunky, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return outputContext.makeImage()
    }

    /// Shifts each block's brightness by a seeded offset in ±`noiseAmplitude` (same offset
    /// for R, G, B so the hue stays, clamped to the premultiplied alpha).
    private static func addBlockNoise(
        to pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, seed: UInt64
    ) {
        var generator = SplitMix64(seed: seed)
        let span = UInt64(2 * noiseAmplitude + 1)
        for y in 0..<height {
            for x in 0..<width {
                let offset = Int(generator.next() % span) - noiseAmplitude
                let pixel = pixels + y * bytesPerRow + x * 4
                let alpha = Int(pixel[3])
                for channel in 0..<3 {
                    pixel[channel] = UInt8(min(alpha, max(0, Int(pixel[channel]) + offset)))
                }
            }
        }
    }

    private static func makeBlurredImage(from image: CGImage, radius: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let outputImage = filter?.outputImage?.cropped(to: ciImage.extent) else { return nil }
        return CIContext().createCGImage(outputImage, from: ciImage.extent)
    }

    public func move(by delta: CGSize) {
        rect.origin.x += delta.width
        rect.origin.y += delta.height
    }

    public func copy() -> any AnnotationObject {
        let copy = PixelateObject(rect: rect, blockSize: blockSize, mode: mode, noiseSeed: noiseSeed)
        copy.style = style
        return copy
    }
}

/// Small seedable generator (SplitMix64): the same seed gives the same block offsets on
/// every render. Not for cryptography; the seed itself comes from the system generator.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
