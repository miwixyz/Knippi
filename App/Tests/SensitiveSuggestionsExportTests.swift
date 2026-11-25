import AppKit
import AnnotationKit
import OCRKit
import XCTest

@testable import Knippi

@MainActor
final class SensitiveSuggestionsExportTests: XCTestCase {
    private func whiteImage(width: Int = 120, height: Int = 60) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// White image with 1-px black/white vertical stripes, like glyph strokes:
    /// readable structure that pixelation has to destroy.
    private func stripedImage(width: Int = 120, height: Int = 60) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: width, by: 2) {
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    /// The stripes are gone: neither pure black nor pure white, and every pixel
    /// of one block reads the same top to bottom and across.
    private func assertPixelated(_ image: CGImage, rect: CGRect, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = Array(try pixel(image, x: Int(rect.minX) + 1, y: Int(rect.minY) + 1).prefix(3))
        let b = Array(try pixel(image, x: Int(rect.minX) + 2, y: Int(rect.maxY) - 1).prefix(3))
        XCTAssertNotEqual(a, [0, 0, 0], "stripe still black", file: file, line: line)
        XCTAssertNotEqual(a, [255, 255, 255], "stripe still white", file: file, line: line)
        XCTAssertEqual(a, b, "one row of blocks, no structure left", file: file, line: line)
    }

    /// RGBA of the pixel at (x, y), top-left origin.
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return data
    }

    private var plainSettings: BeautifySettings {
        var settings = BeautifySettings()
        settings.isEnabled = false
        return settings
    }

    func testExportWithPendingSuggestionsPixelatesThemFirst() throws {
        let image = try stripedImage()
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        let suggestions = SensitiveSuggestionsModel()
        suggestions.show([
            RedactionSuggestion(rect: CGRect(x: 10, y: 10, width: 30, height: 12), isVerified: true),
            RedactionSuggestion(rect: CGRect(x: 70, y: 30, width: 30, height: 12), isVerified: false)
        ])
        // The user deselects the second one: it must stay unredacted.
        suggestions.toggle(try XCTUnwrap(suggestions.items.last).id)
        var appliedCount = 0

        let output = try XCTUnwrap(AnnotationEditorView.renderForExport(
            sourceImage: image,
            document: document,
            suggestions: suggestions,
            beautifySettings: plainSettings,
            outputSize: nil,
            onSuggestionsApplied: { appliedCount += 1 },
            onWarning: { XCTFail("unexpected warning: \($0)") }
        ))

        try assertPixelated(output, rect: CGRect(x: 10, y: 10, width: 30, height: 12))
        XCTAssertEqual(Array(try pixel(output, x: 85, y: 36).prefix(3)), Array(try pixel(image, x: 85, y: 36).prefix(3)), "deselected one is untouched")
        XCTAssertEqual(Array(try pixel(output, x: 86, y: 36).prefix(3)), Array(try pixel(image, x: 86, y: 36).prefix(3)))
        let object = try XCTUnwrap(document.objects.first as? PixelateObject)
        XCTAssertEqual(object.mode, .pixelate)
        XCTAssertNotNil(object.noiseSeed, "confidential text gets block noise")
        XCTAssertEqual(appliedCount, 1)
        XCTAssertFalse(suggestions.isShowing, "suggestions are cleared")
        XCTAssertEqual(document.objects.count, 1)
        document.undo()
        XCTAssertTrue(document.objects.isEmpty, "pixelating is one undo step")
    }

    func testExportWithoutSuggestionsLeavesDocumentAlone() throws {
        let image = try whiteImage()
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        var applied = false
        let output = try XCTUnwrap(AnnotationEditorView.renderForExport(
            sourceImage: image,
            document: document,
            suggestions: SensitiveSuggestionsModel(),
            beautifySettings: plainSettings,
            outputSize: nil,
            onSuggestionsApplied: { applied = true },
            onWarning: { XCTFail("unexpected warning: \($0)") }
        ))
        XCTAssertEqual(Array(try pixel(output, x: 25, y: 16).prefix(3)), [255, 255, 255])
        XCTAssertFalse(applied)
        XCTAssertFalse(document.canUndo)
    }

    // MARK: - Crop output size with a background format

    /// The crop's output size applies to the cropped image; the 16:9 background is drawn
    /// around it afterwards. Before, the 16:9 canvas was squeezed into the crop's 4:3 size.
    func testOutputSizeKeepsBackgroundAspect() throws {
        let image = try whiteImage(width: 400, height: 300)
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        var settings = BeautifySettings()
        settings.isEnabled = true
        settings.aspect = .wide16x9

        let output = try XCTUnwrap(AnnotationEditorView.renderForExport(
            sourceImage: image,
            document: document,
            suggestions: SensitiveSuggestionsModel(),
            beautifySettings: settings,
            outputSize: CGSize(width: 200, height: 150),
            onWarning: { XCTFail("unexpected warning: \($0)") }
        ))

        XCTAssertEqual(Double(output.width) / Double(output.height), 16.0 / 9, accuracy: 0.02)
        let expected = settings.canvasSize(for: CGSize(width: 200, height: 150))
        XCTAssertEqual(output.width, Int(expected.width))
        XCTAssertEqual(output.height, Int(expected.height))
    }

    func testOutputSizeWithoutBeautifyResizesTheCrop() throws {
        let image = try whiteImage(width: 400, height: 300)
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        let output = try XCTUnwrap(AnnotationEditorView.renderForExport(
            sourceImage: image,
            document: document,
            suggestions: SensitiveSuggestionsModel(),
            beautifySettings: plainSettings,
            outputSize: CGSize(width: 200, height: 150),
            onWarning: { XCTFail("unexpected warning: \($0)") }
        ))
        XCTAssertEqual(output.width, 200)
        XCTAssertEqual(output.height, 150)
    }

    // MARK: - Exports while the scan is still running

    /// Holds a scan open until `finish` hands it the regions.
    private final class ScanGate: @unchecked Sendable {
        let stream: AsyncStream<[SensitiveRegion]>
        private let continuation: AsyncStream<[SensitiveRegion]>.Continuation
        init() { (stream, continuation) = AsyncStream.makeStream() }
        func finish(_ regions: [SensitiveRegion]) { continuation.yield(regions); continuation.finish() }
        func regions() async -> [SensitiveRegion] {
            for await regions in stream { return regions }
            return []
        }
    }

    private func startHeldScan(_ suggestions: SensitiveSuggestionsModel, image: CGImage) -> ScanGate {
        let gate = ScanGate()
        suggestions.scan(image: image, screen: nil, findRegions: { _ in await gate.regions() })
        return gate
    }

    private func waitUntilShowing(_ suggestions: SensitiveSuggestionsModel) async throws {
        for _ in 0..<200 where !suggestions.isShowing {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(suggestions.isShowing, "scan results arrived")
    }

    private let secret = SensitiveRegion(
        kind: .email, text: "", boundingBox: CGRect(x: 14, y: 13, width: 22, height: 6), isVerified: true
    )

    func testExportWhileScanningIsBlocked() throws {
        let image = try whiteImage()
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        let suggestions = SensitiveSuggestionsModel()
        let gate = startHeldScan(suggestions, image: image)
        defer { gate.finish([]); suggestions.cancel() }
        XCTAssertTrue(suggestions.isScanning)
        var blocked = 0

        let output = AnnotationEditorView.renderForExport(
            sourceImage: image,
            document: document,
            suggestions: suggestions,
            beautifySettings: plainSettings,
            outputSize: nil,
            onBlockedWhileScanning: { blocked += 1 },
            onWarning: { XCTFail("unexpected warning: \($0)") }
        )

        XCTAssertNil(output, "no unredacted image leaves the editor while the scan runs")
        XCTAssertEqual(blocked, 1, "the user is told why (toast)")
        XCTAssertTrue(suggestions.isScanning, "the scan keeps running")
    }

    func testExportAfterScanResultsAppliesThem() async throws {
        let image = try stripedImage()
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        let suggestions = SensitiveSuggestionsModel()
        let gate = startHeldScan(suggestions, image: image)
        gate.finish([secret])
        try await waitUntilShowing(suggestions)

        let output = try XCTUnwrap(AnnotationEditorView.renderForExport(
            sourceImage: image,
            document: document,
            suggestions: suggestions,
            beautifySettings: plainSettings,
            outputSize: nil,
            onWarning: { XCTFail("unexpected warning: \($0)") }
        ))

        try assertPixelated(output, rect: try XCTUnwrap(document.objects.first).bounds)
        XCTAssertFalse(suggestions.isShowing)
    }

    // MARK: - Crop

    func testCropWhileScanningIsBlocked() throws {
        let image = try whiteImage()
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        let suggestions = SensitiveSuggestionsModel()
        let gate = startHeldScan(suggestions, image: image)
        defer { gate.finish([]); suggestions.cancel() }
        var blocked = 0

        let mayCrop = AnnotationEditorView.beginCrop(
            document: document, suggestions: suggestions, onBlockedWhileScanning: { blocked += 1 }
        )

        XCTAssertFalse(mayCrop, "crop waits for the scan")
        XCTAssertEqual(blocked, 1, "the user is told why")
        XCTAssertTrue(suggestions.isScanning, "the scan is not dropped")
    }

    func testCropAppliesPendingSuggestionsFirst() throws {
        let image = try whiteImage()
        let document = AnnotationDocument(imageSize: CGSize(width: image.width, height: image.height))
        let suggestions = SensitiveSuggestionsModel()
        suggestions.show([RedactionSuggestion(rect: CGRect(x: 10, y: 10, width: 30, height: 12), isVerified: true)])
        var applied = 0

        let mayCrop = AnnotationEditorView.beginCrop(
            document: document, suggestions: suggestions, onSuggestionsApplied: { applied += 1 }
        )

        XCTAssertTrue(mayCrop)
        XCTAssertEqual(applied, 1)
        XCTAssertEqual(document.objects.count, 1, "the pending suggestion was pixelated, not discarded")
        XCTAssertFalse(suggestions.isShowing)
    }

    // MARK: - Drag/share temp file

    func testDragCacheIsInvalidatedOnlyWhenSuggestionsAppear() {
        XCTAssertTrue(AnnotationEditorView.suggestionsChangeInvalidatesDragCache(wasShowing: false, isShowing: true),
                      "a file rendered before the suggestions appeared would skip them")
        XCTAssertFalse(AnnotationEditorView.suggestionsChangeInvalidatesDragCache(wasShowing: true, isShowing: false),
                       "applying them on export must not delete the file just written for share/drag")
    }
}

@MainActor
final class SecureBlockSizeTests: XCTestCase {
    /// Rendered blocks are twice `blockSize`: a text line must end up as one row.
    func testOneRowOfBlocksPerLine() {
        for height in [12.0, 17, 24, 40, 63] {
            let block = SensitiveSuggestionsModel.secureBlockSize(for: CGRect(x: 0, y: 0, width: 200, height: height))
            XCTAssertGreaterThanOrEqual(block * 2, height)
        }
    }

    func testNeverFinerThanTheEditorDefault() {
        XCTAssertEqual(SensitiveSuggestionsModel.secureBlockSize(for: CGRect(x: 0, y: 0, width: 50, height: 6)), 12)
    }
}

@MainActor
final class SensitiveSuggestionsFaceTests: XCTestCase {
    func testFaceBlockSizeGivesAboutSixBlocksAcrossTheWidth() {
        // Gerendert wird mit der doppelten Blockgröße: Breite / (2 × Block) ≈ 6.
        for width in [60.0, 170.0, 400.0] {
            let block = SensitiveSuggestionsModel.faceBlockSize(for: CGRect(x: 0, y: 0, width: width, height: width))
            let across = width / (2 * block)
            XCTAssertLessThanOrEqual(across, 6.01, "width \(width)")
            XCTAssertGreaterThanOrEqual(across, 4.0, "width \(width)")
        }
        XCTAssertGreaterThanOrEqual(SensitiveSuggestionsModel.faceBlockSize(for: CGRect(x: 0, y: 0, width: 10, height: 10)), 4)
    }

    func testFaceSuggestionIsPixelatedWithItsOwnBlockRuleAndNoise() {
        let model = SensitiveSuggestionsModel()
        let face = CGRect(x: 10, y: 10, width: 240, height: 280)
        let text = CGRect(x: 300, y: 20, width: 200, height: 30)
        model.show([RedactionSuggestion(rect: face, isVerified: true, isFace: true),
                    RedactionSuggestion(rect: text, isVerified: true)])
        let document = AnnotationDocument(imageSize: CGSize(width: 600, height: 400))
        XCTAssertTrue(model.applyPendingRedactions(to: document))
        let objects = document.objects.compactMap { $0 as? PixelateObject }
        XCTAssertEqual(objects.count, 2)
        let faceObject = objects.first { $0.rect == face }
        let textObject = objects.first { $0.rect == text }
        XCTAssertEqual(faceObject?.blockSize, SensitiveSuggestionsModel.faceBlockSize(for: face))
        XCTAssertEqual(textObject?.blockSize, SensitiveSuggestionsModel.secureBlockSize(for: text))
        XCTAssertNotNil(faceObject?.noiseSeed)
        XCTAssertEqual(faceObject?.locksStrength, true)
        XCTAssertTrue(faceObject?.mode == RedactionMode.pixelate)
    }

    func testDeselectedFaceIsNotRedacted() {
        let model = SensitiveSuggestionsModel()
        model.show([RedactionSuggestion(rect: CGRect(x: 0, y: 0, width: 100, height: 100), isVerified: false, isFace: true)])
        model.toggle(model.items[0].id)
        XCTAssertFalse(model.applyPendingRedactions(to: AnnotationDocument(imageSize: CGSize(width: 600, height: 400))))
    }
}
