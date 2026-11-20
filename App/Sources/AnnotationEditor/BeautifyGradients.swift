import CoreGraphics

/// The built-in Beautify gradients: a diagonal base plus two soft glows.
/// Pure CoreGraphics so the renderer stays a pure function.
enum BeautifyGradients {
    static func draw(_ g: BeautifyGradient, in ctx: CGContext, rect: CGRect) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                                 CGFloat((hex >> 8) & 0xFF) / 255,
                                                 CGFloat(hex & 0xFF) / 255, a])!
        }
        let (base, glowA, glowB): ([CGColor], CGColor, CGColor) = switch g {
        case .polarlicht: ([c(0x1E4F5E), c(0x2E6F80), c(0x2B2F6B)], c(0x5FE0C8, 0.55), c(0x6D7BFF, 0.45))
        case .abendglut:  ([c(0xFF8A4C), c(0xF2546B), c(0x7B3FA0)], c(0xFFD27A, 0.55), c(0xFF6FA8, 0.40))
        case .graphit:    ([c(0x23293A), c(0x161A25), c(0x0D1019)], c(0x98A9E1, 0.30), c(0x2E6F80, 0.25))
        }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: rect)
        let lin = CGGradient(colorsSpace: cs, colors: base as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(lin, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        let glows = [(glowA, CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY - rect.height * 0.15)),
                     (glowB, CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY + rect.height * 0.2))]
        for (glow, center) in glows {
            let rg = CGGradient(colorsSpace: cs, colors: [glow, glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(rg, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: max(rect.width, rect.height) * 0.7, options: [])
        }
    }

    /// A small rendered copy for previews (tiles, editor backdrop).
    static func image(_ g: BeautifyGradient, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        draw(g, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
