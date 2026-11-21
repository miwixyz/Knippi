import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("Redaction object", .serialized)
struct RedactionObjectTests {
    @Test("Pixelate object copy preserves redaction mode")
    func copyPreservesRedactionMode() {
        let original = PixelateObject(
            rect: CGRect(x: 10, y: 12, width: 40, height: 30),
            blockSize: 16,
            mode: .blur
        )

        let copied = original.copy()
        guard let redactionCopy = copied as? PixelateObject else {
            Issue.record("copy() did not return PixelateObject")
            return
        }

        #expect(redactionCopy.id != original.id)
        #expect(redactionCopy.rect == original.rect)
        #expect(redactionCopy.blockSize == original.blockSize)
        #expect(redactionCopy.mode == .blur)
    }

    /// Audit A1 (21.11.): changing the colour of a selected "Find Sensitive" pixelation
    /// reset its blocks to the line width (3) and made the text readable again.
    @Test("Restyling a secure pixelation never makes it weaker")
    func secureRestyleNeverWeakens() {
        let secure = PixelateObject(rect: .zero, blockSize: 14, mode: .pixelate, noiseSeed: 42)
        secure.restyle(blockSize: 3, mode: .blur)
        #expect(secure.blockSize == 14)
        #expect(secure.mode == .pixelate)
        secure.restyle(blockSize: 20, mode: .solid)
        #expect(secure.blockSize == 20)
        #expect(secure.mode == .solid)
    }

    @Test("Restyling a manual pixelation applies the new values")
    func manualRestyleApplies() {
        let manual = PixelateObject(rect: .zero, blockSize: 14, mode: .pixelate)
        manual.restyle(blockSize: 6, mode: .blur)
        #expect(manual.blockSize == 6)
        #expect(manual.mode == .blur)
    }

    @Test("A hand-drawn pixelation with noise still restyles freely (audit A12)")
    func noisyManualRestyleApplies() {
        let manual = PixelateObject(rect: .zero, blockSize: 14, mode: .pixelate, noiseSeed: 5, locksStrength: false)
        manual.restyle(blockSize: 6, mode: .blur)
        #expect(manual.blockSize == 6)
        #expect(manual.mode == .blur)
        let copy = manual.copy() as? PixelateObject
        #expect(copy?.locksStrength == false)
        #expect(copy?.noiseSeed == 5)
        #expect(PixelateObject(rect: .zero, noiseSeed: 1).locksStrength)
    }

    @Test("Without the source image a pixelation is drawn opaque black (audit A19)")
    func renderWithoutSourceFailsClosed() throws {
        let ctx = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        for mode in [RedactionMode.pixelate, .blur] {
            PixelateObject(rect: CGRect(x: 0, y: 0, width: 8, height: 8), mode: mode).render(in: ctx)
            let image = try #require(ctx.makeImage())
            #expect(sampleRGBA(image, x: 4, y: 4) == RGBA(r: 0, g: 0, b: 0, a: 255))
        }
    }

    @Test("Solid redaction renders a flat filled region")
    func solidRedactionRendersFill() throws {
        let source = try makeTestImage(width: 8, height: 8, color: CGColor(gray: 1, alpha: 1))
        let redaction = PixelateObject(
            rect: CGRect(x: 2, y: 2, width: 4, height: 4),
            blockSize: 12,
            mode: .solid
        )
        redaction.style = StrokeStyle(color: .black, lineWidth: 1, opacity: 1)

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 3, y: 3) == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(sampleRGBA(rendered, x: 0, y: 0) == RGBA(r: 255, g: 255, b: 255, a: 255))
    }

    @Test("Solid redaction is always opaque black, regardless of stroke style")
    func solidRedactionIgnoresStyle() throws {
        let source = try makeTestImage(width: 8, height: 8, color: CGColor(gray: 1, alpha: 1))
        let redaction = PixelateObject(rect: CGRect(x: 2, y: 2, width: 4, height: 4), blockSize: 12, mode: .solid)
        redaction.style = StrokeStyle(color: .red, lineWidth: 3, opacity: 0.4)
        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        #expect(sampleRGBA(rendered, x: 3, y: 3) == RGBA(r: 0, g: 0, b: 0, a: 255))
    }

    @Test("Blur redaction changes source pixels inside the selected region")
    func blurRedactionChangesInteriorPixels() throws {
        let source = try makeSplitImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 4, y: 4, width: 8, height: 8),
            blockSize: 12,
            mode: .blur
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 7, y: 7) != sampleRGBA(source, x: 7, y: 7))
        #expect(sampleRGBA(rendered, x: 1, y: 1) == sampleRGBA(source, x: 1, y: 1))
    }

    @Test("Blur keeps nothing finer than a block, so it can't be reversed")
    func blurDropsDetailInsideBlocks() throws {
        let size = 192
        func blurred(squareAt origin: CGPoint) throws -> CGImage {
            let context = try #require(makeBitmapContext(width: size, height: size))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: origin, size: CGSize(width: 12, height: 12)))
            let source = try #require(context.makeImage())
            let redaction = PixelateObject(rect: CGRect(x: 0, y: 0, width: size, height: size), blockSize: 12, mode: .blur)
            return try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        }
        // Opposite corners of the same 24 px block.
        let a = try blurred(squareAt: CGPoint(x: 96, y: 96))
        let b = try blurred(squareAt: CGPoint(x: 108, y: 108))
        var largest = 0
        for y in stride(from: 48, to: 160, by: 4) {
            for x in stride(from: 48, to: 160, by: 4) {
                largest = max(largest, abs(Int(sampleRGBA(a, x: x, y: y).r) - Int(sampleRGBA(b, x: x, y: y).r)))
            }
        }
        #expect(largest <= 2)
    }

    @Test("Pixelate redaction renders repeated block pixels")
    func pixelateRedactionRendersBlockPixels() throws {
        let source = try makeHorizontalGradientImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 0, y: 0, width: 16, height: 16),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 1, y: 8) == sampleRGBA(rendered, x: 6, y: 8))
        #expect(sampleRGBA(rendered, x: 1, y: 8) != sampleRGBA(rendered, x: 10, y: 8))
    }

    @Test("Pixelate samples the selected top-left source region")
    func pixelateSamplesSelectedTopLeftSourceRegion() throws {
        let source = try makeQuadrantImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 0, y: 0, width: 8, height: 8),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        let sampled = sampleRGBA(rendered, x: 3, y: 3)

        #expect(sampled.r > 200)
        #expect(sampled.b < 80)
    }

    @Test("Pixelate samples the selected top-right source region")
    func pixelateSamplesSelectedTopRightSourceRegion() throws {
        let source = try makeQuadrantImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 8, y: 0, width: 8, height: 8),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        let sampled = sampleRGBA(rendered, x: 11, y: 3)

        #expect(sampled.g > 180)
        #expect(sampled.r < 100)
        #expect(sampled.b < 100)
    }

    @Test("Pixelate draws inside the selected region in a flipped scaled canvas")
    func pixelateDrawsInsideSelectedRegionInFlippedScaledCanvas() throws {
        let source = try makeQuadrantImage(width: 16, height: 16)
        let redaction = PixelateObject(
            rect: CGRect(x: 8, y: 0, width: 8, height: 8),
            blockSize: 4,
            mode: .pixelate
        )

        let rendered = try #require(renderFlippedCanvas(source: source, objects: [redaction], zoomScale: 2))
        let sampled = sampleRGBA(rendered, x: 22, y: 6)

        #expect(sampled.g > 180)
        #expect(sampled.r < 100)
        #expect(sampled.b < 100)
    }

    @Test("Pixelate falls back to a solid black fill when the filter fails")
    func pixelateFailsClosed() throws {
        let source = try makeTestImage(width: 16, height: 16, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let redaction = PixelateObject(
            rect: CGRect(x: 4, y: 4, width: 8, height: 8),
            blockSize: 12,
            mode: .pixelate
        )
        PixelateObject.redactorOverride = { _, _, _ in nil }
        defer { PixelateObject.redactorOverride = nil }

        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))

        #expect(sampleRGBA(rendered, x: 8, y: 8) == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(sampleRGBA(rendered, x: 1, y: 1) == RGBA(r: 255, g: 255, b: 255, a: 255))
    }

    @Test("Fail-closed fill lands on the top-left region, not its mirror")
    func pixelateFailsClosedAsymmetric() throws {
        let source = try makeTestImage(width: 16, height: 16, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let redaction = PixelateObject(rect: CGRect(x: 2, y: 1, width: 6, height: 4), blockSize: 12, mode: .pixelate)
        PixelateObject.redactorOverride = { _, _, _ in nil }
        defer { PixelateObject.redactorOverride = nil }
        let rendered = try #require(AnnotationRenderer.render(sourceImage: source, objects: [redaction]))
        #expect(sampleRGBA(rendered, x: 2, y: 1) == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(sampleRGBA(rendered, x: 7, y: 4) == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(sampleRGBA(rendered, x: 7, y: 5) == RGBA(r: 255, g: 255, b: 255, a: 255))
        #expect(sampleRGBA(rendered, x: 4, y: 12) == RGBA(r: 255, g: 255, b: 255, a: 255))
    }

    /// Audit A13 (21.11.): every canvas draw re-ran pixelate/blur (measured 8 ms / 38 ms per
    /// 2000x800 region). The result is now cached per object until something it depends on changes.
    @Test("Redaction result is cached until rect, block size, mode, seed or source change")
    func redactionIsCached() throws {
        let source = try makeTestImage(width: 32, height: 32, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let other = try makeTestImage(width: 32, height: 32, color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        let counter = CallCounter()
        PixelateObject.redactorOverride = { image, _, _ in counter.count += 1; return image }
        defer { PixelateObject.redactorOverride = nil }
        let context = try #require(makeBitmapContext(width: 32, height: 32))
        let redaction = PixelateObject(rect: CGRect(x: 4, y: 4, width: 16, height: 16), blockSize: 8, mode: .pixelate)

        redaction.renderWithSource(in: context, sourceImage: source)
        redaction.renderWithSource(in: context, sourceImage: source)
        #expect(counter.count == 1)

        redaction.move(by: CGSize(width: 2, height: 0))
        redaction.renderWithSource(in: context, sourceImage: source)
        #expect(counter.count == 2)

        redaction.blockSize = 10
        redaction.renderWithSource(in: context, sourceImage: source)
        #expect(counter.count == 3)

        redaction.mode = .blur
        redaction.renderWithSource(in: context, sourceImage: source)
        #expect(counter.count == 4)

        redaction.noiseSeed = 7
        redaction.renderWithSource(in: context, sourceImage: source)
        #expect(counter.count == 5)

        redaction.renderWithSource(in: context, sourceImage: other)
        #expect(counter.count == 6)
        redaction.renderWithSource(in: context, sourceImage: other)
        #expect(counter.count == 6)
    }

    @Test("A failed redaction is not cached and keeps failing closed")
    func failedRedactionIsNotCached() throws {
        let source = try makeTestImage(width: 16, height: 16, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let counter = CallCounter()
        PixelateObject.redactorOverride = { _, _, _ in counter.count += 1; return nil }
        defer { PixelateObject.redactorOverride = nil }
        let context = try #require(makeBitmapContext(width: 16, height: 16))
        let redaction = PixelateObject(rect: CGRect(x: 4, y: 4, width: 8, height: 8), mode: .pixelate)
        redaction.renderWithSource(in: context, sourceImage: source)
        redaction.renderWithSource(in: context, sourceImage: source)
        #expect(counter.count == 2)
    }
}

private final class CallCounter: @unchecked Sendable {
    var count = 0
}

private struct RGBA: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

private func makeTestImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    context.setFillColor(color)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private func makeSplitImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
    return try #require(context.makeImage())
}

private func makeHorizontalGradientImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    for x in 0..<width {
        let gray = CGFloat(x) / CGFloat(max(1, width - 1))
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    return try #require(context.makeImage())
}

private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(makeBitmapContext(width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
    return try #require(context.makeImage())
}

private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private func renderFlippedCanvas(
    source: CGImage,
    objects: [any AnnotationObject],
    zoomScale: CGFloat
) -> CGImage? {
    let width = Int(CGFloat(source.width) * zoomScale)
    let height = Int(CGFloat(source.height) * zoomScale)
    guard let context = makeBitmapContext(width: width, height: height) else { return nil }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.scaleBy(x: zoomScale, y: zoomScale)

    let imageRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(source.height))
    context.scaleBy(x: 1, y: -1)
    context.draw(source, in: imageRect)
    context.restoreGState()

    for object in objects {
        if let pixelate = object as? PixelateObject {
            pixelate.renderWithSource(in: context, sourceImage: source)
        } else {
            object.render(in: context)
        }
    }

    return context.makeImage()
}

private func sampleRGBA(_ image: CGImage, x: Int, y: Int) -> RGBA {
    let context = makeBitmapContext(width: 1, height: 1)!
    context.draw(
        image,
        in: CGRect(
            x: -x,
            y: -(image.height - 1 - y),
            width: image.width,
            height: image.height
        )
    )
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    return RGBA(r: data[0], g: data[1], b: data[2], a: data[3])
}
