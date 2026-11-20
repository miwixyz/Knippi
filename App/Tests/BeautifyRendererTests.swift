import AppKit
import SharedKit
import SwiftUI
import XCTest
@testable import Knippi

final class BeautifyRendererTests: XCTestCase {
    func testTransparentImageCornersShowTheBackground() throws {
        // A window capture: opaque content with its own transparent rounded corners,
        // more rounded than the Beautify corner radius.
        let size = 200
        let window = try XCTUnwrap(Self.context(width: size, height: size))
        window.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: 40, cornerHeight: 40, transform: nil))
        window.clip()
        window.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        window.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(window.makeImage())

        var settings = BeautifySettings()
        settings.isEnabled = true
        settings.backgroundColor = .black
        settings.padding = 20
        settings.cornerRadius = 8
        settings.shadowEnabled = true
        let output = try XCTUnwrap(BeautifyRenderer.render(image: image, settings: settings)).image

        let rep = NSBitmapImageRep(cgImage: output)
        let inset = Int(settings.outerInset)
        // Inside the 8 px Beautify corner but outside the window's own 40 px corner.
        let corner = try XCTUnwrap(rep.colorAt(x: inset + 4, y: inset + 4)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(corner.redComponent + corner.greenComponent + corner.blueComponent, 0.3, "\(corner)")

        let center = try XCTUnwrap(rep.colorAt(x: inset + size / 2, y: inset + size / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, 0.9)
    }

    func testNoBackgroundLeavesOnlyRoundedCorners() throws {
        let size = 100
        let ctx = try XCTUnwrap(Self.context(width: size, height: size))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(ctx.makeImage())

        var settings = BeautifySettings()
        settings.isEnabled = true
        settings.backgroundStyle = .none
        settings.padding = 0
        settings.cornerRadius = 20
        settings.shadowEnabled = false
        let output = try XCTUnwrap(BeautifyRenderer.render(image: image, settings: settings)).image

        XCTAssertEqual(output.width, size)
        let rep = NSBitmapImageRep(cgImage: output)
        XCTAssertEqual(try XCTUnwrap(rep.colorAt(x: 1, y: 1)).alphaComponent, 0)
        XCTAssertEqual(try XCTUnwrap(rep.colorAt(x: size / 2, y: size / 2)).alphaComponent, 1)
    }

    func testSavedStyleRoundTripsWithBeautifyOff() throws {
        let suite = "BeautifyStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        var style = BeautifySettings()
        style.isEnabled = true
        style.backgroundStyle = .liquidGlass
        style.backgroundColor = Color(nsColor: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        style.padding = 24
        style.cornerRadius = 18
        style.shadowEnabled = false
        style.shadowRadius = 10
        style.saveStyle(settings: settings)

        let loaded = BeautifySettings.saved(settings: settings)
        XCTAssertFalse(loaded.isEnabled)
        XCTAssertEqual(loaded.backgroundStyle, .liquidGlass)
        XCTAssertEqual(loaded.padding, 24)
        XCTAssertEqual(loaded.cornerRadius, 18)
        XCTAssertFalse(loaded.shadowEnabled)
        XCTAssertEqual(loaded.shadowRadius, 10)
        let color = try XCTUnwrap(NSColor(loaded.backgroundColor).usingColorSpace(.sRGB))
        XCTAssertEqual(color.blueComponent, 0.6, accuracy: 0.01)
    }

    // MARK: - Aspect formats

    func testSquareFormatMakesWideImageSquare() throws {
        var settings = Self.enabledSettings()
        settings.aspect = .square1x1
        let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: 300, height: 100), settings: settings))
        XCTAssertEqual(output.image.width, output.image.height)
        XCTAssertGreaterThanOrEqual(output.image.width, 380)
        XCTAssertNil(output.warning)
    }

    func testWideFormatMatchesSixteenByNine() throws {
        for (w, h) in [(300, 100), (100, 300), (400, 400)] {
            var settings = Self.enabledSettings()
            settings.aspect = .wide16x9
            let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: w, height: h), settings: settings)).image
            XCTAssertEqual(CGFloat(output.height) * 16 / 9, CGFloat(output.width), accuracy: 1.5, "\(w)x\(h) -> \(output.width)x\(output.height)")
            XCTAssertGreaterThanOrEqual(output.width, w + 80)
            XCTAssertGreaterThanOrEqual(output.height, h + 80)
        }
    }

    func testPortraitFormatCentresImage() throws {
        var settings = Self.enabledSettings()
        settings.aspect = .portrait4x5
        settings.shadowEnabled = false
        settings.cornerRadius = 0
        settings.backgroundColor = .black
        let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: 200, height: 100), settings: settings)).image
        XCTAssertEqual(CGFloat(output.width) * 5 / 4, CGFloat(output.height), accuracy: 1.5)
        let rep = NSBitmapImageRep(cgImage: output)
        let center = try XCTUnwrap(rep.colorAt(x: output.width / 2, y: output.height / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, 0.9, "image sits in the middle")
        let top = try XCTUnwrap(rep.colorAt(x: output.width / 2, y: 5)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(top.redComponent, 0.1, "extra height is background")
    }

    func testFreeFormatKeepsUniformPadding() throws {
        let settings = Self.enabledSettings()
        let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: 300, height: 100), settings: settings)).image
        XCTAssertEqual(output.width, 300 + Int(settings.outerInset) * 2)
        XCTAssertEqual(output.height, 100 + Int(settings.outerInset) * 2)
    }

    // MARK: - Backgrounds

    func testGradientIsNotFlat() throws {
        var settings = Self.enabledSettings()
        settings.backgroundStyle = .gradient(.polarlicht)
        let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: 100, height: 100), settings: settings))
        XCTAssertNil(output.warning)
        let rep = NSBitmapImageRep(cgImage: output.image)
        let topLeft = try XCTUnwrap(rep.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        let bottomRight = try XCTUnwrap(rep.colorAt(x: output.image.width - 2, y: output.image.height - 2)?.usingColorSpace(.deviceRGB))
        let delta = abs(topLeft.redComponent - bottomRight.redComponent)
            + abs(topLeft.greenComponent - bottomRight.greenComponent)
            + abs(topLeft.blueComponent - bottomRight.blueComponent)
        XCTAssertGreaterThan(delta, 0.1, "\(topLeft) vs \(bottomRight)")
        XCTAssertEqual(topLeft.alphaComponent, 1)
    }

    func testMissingCustomImageFallsBackToSolidWithWarning() throws {
        var settings = Self.enabledSettings()
        settings.backgroundColor = .black
        settings.backgroundStyle = .image(URL(fileURLWithPath: "/nonexistent/knippi-\(UUID().uuidString).png"))
        let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: 100, height: 100), settings: settings))
        XCTAssertNotNil(output.warning)
        let corner = try XCTUnwrap(NSBitmapImageRep(cgImage: output.image).colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(corner.alphaComponent, 1)
        XCTAssertLessThan(corner.redComponent + corner.greenComponent + corner.blueComponent, 0.05, "solid fallback")
    }

    func testCustomImageFillsBackground() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("knippi-bg-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = try XCTUnwrap(Self.context(width: 20, height: 10))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        let bg = try XCTUnwrap(ctx.makeImage())
        try XCTUnwrap(ImageUtilities.pngData(from: bg)).write(to: url)

        var settings = Self.enabledSettings()
        settings.backgroundStyle = .image(url)
        settings.aspect = .portrait4x5
        let output = try XCTUnwrap(BeautifyRenderer.render(image: try Self.opaqueImage(width: 100, height: 100), settings: settings))
        XCTAssertNil(output.warning)
        let corner = try XCTUnwrap(NSBitmapImageRep(cgImage: output.image).colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(corner.greenComponent, 0.9)
        XCTAssertLessThan(corner.redComponent, 0.1)
    }

    // MARK: - Persistence

    /// Exactly what the pre-B6 `saveStyle` wrote (no aspect, plain style string).
    func testStyleSavedBeforeGradientsStillLoads() throws {
        let (settings, cleanup) = try Self.isolatedSettings()
        defer { cleanup() }
        settings.beautifyStyle = Data(#"{"backgroundStyle":"liquidGlass","backgroundColor":[0.2,0.4,0.6,1],"padding":24,"cornerRadius":18,"shadowEnabled":false,"shadowRadius":10}"#.utf8)

        let loaded = BeautifySettings.saved(settings: settings)
        XCTAssertEqual(loaded.backgroundStyle, .liquidGlass)
        XCTAssertEqual(loaded.aspect, .free)
        XCTAssertEqual(loaded.padding, 24)
        XCTAssertEqual(loaded.cornerRadius, 18)
        XCTAssertFalse(loaded.shadowEnabled)
        XCTAssertEqual(loaded.shadowRadius, 10)
        let color = try XCTUnwrap(NSColor(loaded.backgroundColor).usingColorSpace(.sRGB))
        XCTAssertEqual(color.blueComponent, 0.6, accuracy: 0.01)

        for (raw, expected) in [("solid", BeautifyBackgroundStyle.solid), ("none", .none)] {
            settings.beautifyStyle = Data(#"{"backgroundStyle":"\#(raw)","backgroundColor":[1,1,1,1],"padding":40,"cornerRadius":12,"shadowEnabled":true,"shadowRadius":20}"#.utf8)
            XCTAssertEqual(BeautifySettings.saved(settings: settings).backgroundStyle, expected)
        }
    }

    func testUnknownStoredValuesFallBackToDefaults() throws {
        let (settings, cleanup) = try Self.isolatedSettings()
        defer { cleanup() }
        settings.beautifyStyle = Data(#"{"backgroundStyle":"hologram","aspect":"cinemascope","padding":30}"#.utf8)
        let loaded = BeautifySettings.saved(settings: settings)
        XCTAssertEqual(loaded.backgroundStyle, .solid)
        XCTAssertEqual(loaded.aspect, .free)
        XCTAssertEqual(loaded.padding, 30)
        XCTAssertEqual(loaded.cornerRadius, 12)

        settings.beautifyStyle = Data("not json".utf8)
        XCTAssertEqual(BeautifySettings.saved(settings: settings).padding, 40)
    }

    func testGradientImageAndAspectRoundTrip() throws {
        let (settings, cleanup) = try Self.isolatedSettings()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/someone/Pictures/Hintergrund mit Leerzeichen.jpg")
        for style in [BeautifyBackgroundStyle.gradient(.abendglut), .gradient(.graphit), .image(url), .none] {
            var s = BeautifySettings()
            s.backgroundStyle = style
            s.aspect = .portrait4x5
            s.saveStyle(settings: settings)
            let loaded = BeautifySettings.saved(settings: settings)
            XCTAssertEqual(loaded.backgroundStyle, style)
            XCTAssertEqual(loaded.aspect, .portrait4x5)
        }
    }

    /// Writes one sample per gradient and format for a visual check when
    /// `TEST_RUNNER_BEAUTIFY_SAMPLE_DIR` is set; otherwise a no-op.
    func testWriteSamplesForVisualCheck() throws {
        guard let dir = ProcessInfo.processInfo.environment["BEAUTIFY_SAMPLE_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shot = try Self.opaqueImage(width: 600, height: 380)
        for gradient in BeautifyGradient.allCases {
            for aspect in BeautifyAspect.allCases {
                var settings = Self.enabledSettings()
                settings.backgroundStyle = .gradient(gradient)
                settings.aspect = aspect
                let output = try XCTUnwrap(BeautifyRenderer.render(image: shot, settings: settings)).image
                try XCTUnwrap(ImageUtilities.pngData(from: output))
                    .write(to: folder.appendingPathComponent("\(gradient.rawValue)-\(aspect.rawValue).png"))
            }
        }
    }

    private static func enabledSettings() -> BeautifySettings {
        var settings = BeautifySettings()
        settings.isEnabled = true
        return settings
    }

    private static func opaqueImage(width: Int, height: Int) throws -> CGImage {
        let ctx = try XCTUnwrap(context(width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    private static func isolatedSettings() throws -> (AppSettings, () -> Void) {
        let suite = "BeautifyStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (AppSettings(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
