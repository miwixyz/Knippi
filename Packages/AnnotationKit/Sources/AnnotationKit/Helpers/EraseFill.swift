import CoreGraphics
import Foundation

/// Füllung für „Entfernen“ (Smart erase): die Fläche wird allein aus den Randpixeln
/// *außerhalb* des Rechtecks berechnet (Coons-Fläche aus bilinearer Interpolation der vier
/// Ränder) plus ein leichtes, festes Rauschen. Das Original im Inneren geht nie in die
/// Rechnung ein, also lässt sich aus dem Ergebnis nichts davon zurückrechnen.
public enum EraseFill {
    /// Breite des Randstreifens, der je Seite gemittelt wird (Pixel).
    static let bandDepth = 2
    /// Rauschen je Pixel in 8-Bit-Stufen (± dieser Wert), gleich für R, G, B.
    static let noiseAmplitude = 3

    struct RGB { var r: Double; var g: Double; var b: Double }

    /// Liefert das Füllbild für `rect` (Bildpixel, links oben). `nil` bei leerem Rechteck oder
    /// wenn kein Bitmap angelegt werden kann; der Aufrufer schwärzt dann deckend.
    public static func makeImage(source: CGImage, rect: CGRect, noiseSeed: UInt64?) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        let x0 = Int(r.minX), y0 = Int(r.minY), w = Int(r.width), h = Int(r.height)
        let d = bandDepth

        // Fenster = Rechteck plus Rand (soweit im Bild), nur dieses wird gelesen.
        let wx0 = max(0, x0 - d), wy0 = max(0, y0 - d)
        let wx1 = min(source.width, x0 + w + d), wy1 = min(source.height, y0 + h + d)
        let ww = wx1 - wx0, wh = wy1 - wy0
        guard let window = source.cropping(to: CGRect(x: wx0, y: wy0, width: ww, height: wh)),
              let ctx = CGContext(
                data: nil, width: ww, height: wh, bitsPerComponent: 8, bytesPerRow: ww * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Auf deckend weiß zeichnen, damit Transparenz keine Spur hinterlässt.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ww, height: wh))
        ctx.draw(window, in: CGRect(x: 0, y: 0, width: ww, height: wh))
        guard let base = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stride = ctx.bytesPerRow

        func pixel(_ x: Int, _ y: Int) -> RGB {   // x, y in Bildkoordinaten, im Fenster
            let p = base + (y - wy0) * stride + (x - wx0) * 4
            return RGB(r: Double(p[0]), g: Double(p[1]), b: Double(p[2]))
        }
        func mean(_ items: [RGB]) -> RGB {
            let n = Double(items.count)
            return RGB(r: items.reduce(0) { $0 + $1.r } / n,
                       g: items.reduce(0) { $0 + $1.g } / n,
                       b: items.reduce(0) { $0 + $1.b } / n)
        }

        let hasTop = y0 - d >= 0, hasBottom = y0 + h + d <= source.height
        let hasLeft = x0 - d >= 0, hasRight = x0 + w + d <= source.width

        // Randverläufe: top/bottom je Spalte, left/right je Zeile (außerhalb des Rechtecks).
        func column(_ x: Int, above: Bool) -> RGB {
            mean((1...d).map { pixel(x, above ? y0 - $0 : y0 + h - 1 + $0) })
        }
        func row(_ y: Int, leftSide: Bool) -> RGB {
            mean((1...d).map { pixel(leftSide ? x0 - $0 : x0 + w - 1 + $0, y) })
        }
        var top = hasTop ? (0..<w).map { column(x0 + $0, above: true) } : []
        var bottom = hasBottom ? (0..<w).map { column(x0 + $0, above: false) } : []
        var left = hasLeft ? (0..<h).map { row(y0 + $0, leftSide: true) } : []
        var right = hasRight ? (0..<h).map { row(y0 + $0, leftSide: false) } : []

        // Fehlt eine Seite (Rechteck am Bildrand), nimmt sie den Verlauf der Gegenseite;
        // fehlt auch der Rest, bleibt neutrales Grau. Nie Innenpixel.
        let grey = RGB(r: 128, g: 128, b: 128)
        if top.isEmpty { top = bottom }
        if bottom.isEmpty { bottom = top }
        if left.isEmpty { left = right }
        if right.isEmpty { right = left }
        if top.isEmpty && left.isEmpty {
            top = Array(repeating: grey, count: w); bottom = top
            left = Array(repeating: grey, count: h); right = left
        } else if top.isEmpty {
            // Nur Links/Rechts bekannt: Ober-/Unterkante aus deren Enden.
            top = (0..<w).map { lerp(left[0], right[0], t: w > 1 ? Double($0) / Double(w - 1) : 0) }
            bottom = (0..<w).map { lerp(left[h - 1], right[h - 1], t: w > 1 ? Double($0) / Double(w - 1) : 0) }
        } else if left.isEmpty {
            left = (0..<h).map { lerp(top[0], bottom[0], t: h > 1 ? Double($0) / Double(h - 1) : 0) }
            right = (0..<h).map { lerp(top[w - 1], bottom[w - 1], t: h > 1 ? Double($0) / Double(h - 1) : 0) }
        }

        // Ecken so wählen, dass die Fläche die Ränder trifft (Coons: Randsummen minus bilineare Ecken).
        let c00 = lerp(top[0], left[0], t: 0.5), c10 = lerp(top[w - 1], right[0], t: 0.5)
        let c01 = lerp(bottom[0], left[h - 1], t: 0.5), c11 = lerp(bottom[w - 1], right[h - 1], t: 0.5)

        guard let out = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dst = out.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }
        let outStride = out.bytesPerRow
        var generator = SplitMix64(seed: noiseSeed ?? 0)
        let span = UInt64(2 * noiseAmplitude + 1)

        for j in 0..<h {
            let v = h > 1 ? Double(j) / Double(h - 1) : 0.5
            for i in 0..<w {
                let u = w > 1 ? Double(i) / Double(w - 1) : 0.5
                let p = dst + j * outStride + i * 4
                let t = top[i], b = bottom[i], l = left[j], rr = right[j]
                let noise = noiseSeed == nil ? 0 : Double(Int(generator.next() % span) - noiseAmplitude)
                func channel(_ k: KeyPath<RGB, Double>) -> UInt8 {
                    let ruled = (1 - v) * t[keyPath: k] + v * b[keyPath: k]
                        + (1 - u) * l[keyPath: k] + u * rr[keyPath: k]
                    let corners = (1 - u) * (1 - v) * c00[keyPath: k] + u * (1 - v) * c10[keyPath: k]
                        + (1 - u) * v * c01[keyPath: k] + u * v * c11[keyPath: k]
                    // Coons-Fläche: beide Randpaare addiert, die bilinearen Ecken einmal abgezogen.
                    let value = (ruled - corners) + noise
                    return UInt8(min(255, max(0, value.rounded())))
                }
                p[0] = channel(\.r); p[1] = channel(\.g); p[2] = channel(\.b); p[3] = 255
            }
        }
        return out.makeImage()
    }

    private static func lerp(_ a: RGB, _ b: RGB, t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }
}
