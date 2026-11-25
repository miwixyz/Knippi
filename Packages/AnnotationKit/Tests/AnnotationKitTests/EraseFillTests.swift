import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("Erase fill", .serialized)
struct EraseFillTests {
    /// RGBA-Bild aus einer Funktion (x, y) -> (r, g, b), deckend.
    private func image(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CGImage {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let c = f(x, y); let i = (y * w + x) * 4
            data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2
        } }
        let provider = try #require(CGDataProvider(data: Data(data) as CFData))
        return try #require(CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        let ctx = try #require(CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }

    private let box = CGRect(x: 20, y: 20, width: 40, height: 20)

    @Test("Einfarbiger Grund: Text darauf verschwindet ohne Rauschen restlos")
    func flatBackgroundIsRestored() throws {
        let src = try image(100, 80) { x, y in
            box.contains(CGPoint(x: x, y: y)) && (x + y) % 3 == 0 ? (0, 0, 0) : (200, 120, 40)
        }
        let out = try pixels(try #require(EraseFill.makeImage(source: src, rect: box, noiseSeed: nil)))
        for i in stride(from: 0, to: out.count, by: 4) {
            #expect(out[i] == 200 && out[i + 1] == 120 && out[i + 2] == 40 && out[i + 3] == 255)
        }
    }

    @Test("Weicher Verlauf wird fortgesetzt (bilinear)")
    func gradientContinues() throws {
        let src = try image(100, 80) { x, _ in (UInt8(x * 2), 50, 50) }
        let out = try pixels(try #require(EraseFill.makeImage(source: src, rect: box, noiseSeed: nil)))
        let w = Int(box.width)
        for x in [0, 10, 39] {
            let expected = Int((box.minX + CGFloat(x)) * 2)
            let value = Int(out[(5 * w + x) * 4])
            #expect(abs(value - expected) <= 3, "x=\(x): \(value) statt \(expected)")
        }
    }

    @Test("Der alte Inhalt ist nicht rückrechenbar: Differenzbild zweier Quellen mit anderem Innenleben ist null")
    func interiorNeverInfluencesResult() throws {
        let a = try image(100, 80) { x, y in
            box.contains(CGPoint(x: x, y: y)) ? (UInt8((x * 7) % 256), UInt8((y * 13) % 256), 0) : (90, 90, 200)
        }
        let b = try image(100, 80) { x, y in box.contains(CGPoint(x: x, y: y)) ? (255, 255, 255) : (90, 90, 200) }
        let outA = try pixels(try #require(EraseFill.makeImage(source: a, rect: box, noiseSeed: 7)))
        let outB = try pixels(try #require(EraseFill.makeImage(source: b, rect: box, noiseSeed: 7)))
        #expect(outA == outB)
    }

    @Test("Rauschen ist fest je Seed, klein, und nur mit Seed vorhanden")
    func noiseIsDeterministicAndSmall() throws {
        let src = try image(100, 80) { _, _ in (128, 128, 128) }
        let n1 = try pixels(try #require(EraseFill.makeImage(source: src, rect: box, noiseSeed: 5)))
        let n2 = try pixels(try #require(EraseFill.makeImage(source: src, rect: box, noiseSeed: 5)))
        let n3 = try pixels(try #require(EraseFill.makeImage(source: src, rect: box, noiseSeed: 6)))
        #expect(n1 == n2)
        #expect(n1 != n3)
        for i in stride(from: 0, to: n1.count, by: 4) { #expect(abs(Int(n1[i]) - 128) <= EraseFill.noiseAmplitude) }
    }

    @Test("Am Bildrand und über das ganze Bild bleibt es deckend und liest nie das Innere")
    func edgeCasesStayOpaque() throws {
        let src = try image(40, 30) { _, _ in (10, 200, 10) }
        for rect in [CGRect(x: 0, y: 0, width: 15, height: 10), CGRect(x: 0, y: 0, width: 40, height: 30),
                     CGRect(x: 25, y: 20, width: 15, height: 10), CGRect(x: 0, y: 5, width: 40, height: 5)] {
            let out = try pixels(try #require(EraseFill.makeImage(source: src, rect: rect, noiseSeed: nil)))
            #expect(out.count == Int(rect.width * rect.height) * 4)
            for i in stride(from: 3, to: out.count, by: 4) { #expect(out[i] == 255) }
        }
        let full = try pixels(try #require(EraseFill.makeImage(
            source: src, rect: CGRect(x: 0, y: 0, width: 40, height: 30), noiseSeed: nil)))
        #expect(full[0] == 128, "ganzes Bild: neutrales Grau statt Innenpixel")
    }

    @Test("Leeres Rechteck liefert nil")
    func emptyRect() throws {
        let src = try image(10, 10) { _, _ in (0, 0, 0) }
        #expect(EraseFill.makeImage(source: src, rect: .zero, noiseSeed: nil) == nil)
    }

    // MARK: Modus

    @Test("Rohwerte der Modi bleiben stabil, Erase kommt hinten")
    func rawValues() {
        #expect(RedactionMode.pixelate.rawValue == 0)
        #expect(RedactionMode.blur.rawValue == 1)
        #expect(RedactionMode.solid.rawValue == 2)
        #expect(RedactionMode.erase.rawValue == 3)
    }

    @Test("Restyle schwächt Erase nie ab, Balken darf es ersetzen")
    func restyleNeverWeakensErase() {
        let o = PixelateObject(rect: .zero, blockSize: 14, mode: .erase, noiseSeed: 1)
        o.restyle(blockSize: 3, mode: .pixelate)
        #expect(o.mode == .erase)
        o.restyle(blockSize: 3, mode: .blur)
        #expect(o.mode == .erase)
        o.restyle(blockSize: 3, mode: .solid)
        #expect(o.mode == .solid)
        o.restyle(blockSize: 3, mode: .erase)
        #expect(o.mode == .solid)
    }

    @Test("Gesperrtes Verpixeln darf zu Erase verstärkt werden")
    func lockedPixelateCanStrengthen() {
        let o = PixelateObject(rect: .zero, blockSize: 14, mode: .pixelate, noiseSeed: 1)
        o.restyle(blockSize: 3, mode: .erase)
        #expect(o.mode == .erase)
    }

    @Test("Erase im Renderer: Text auf einfarbigem Grund verschwindet, Umgebung bleibt")
    func rendererErases() throws {
        let src = try image(100, 80) { x, y in
            box.contains(CGPoint(x: x, y: y)) && (x + y) % 2 == 0 ? (0, 0, 0) : (250, 250, 250)
        }
        let o = PixelateObject(rect: box, mode: .erase)
        let rendered = try #require(AnnotationRenderer.render(sourceImage: src, objects: [o]))
        let p = try pixels(rendered)
        func px(_ x: Int, _ y: Int) -> UInt8 { p[(y * 100 + x) * 4] }
        for (x, y) in [(22, 22), (30, 30), (45, 35), (58, 38)] { #expect(px(x, y) == 250) }
        #expect(px(5, 5) == 250)
    }
}
