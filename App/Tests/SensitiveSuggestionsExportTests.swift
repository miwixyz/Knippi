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

    func testExportWithPendingSuggestionsBlacksThemOutFirst() throws {
        let image = try whiteImage()
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

        XCTAssertEqual(Array(try pixel(output, x: 25, y: 16).prefix(3)), [0, 0, 0], "selected suggestion is black")
        XCTAssertEqual(Array(try pixel(output, x: 85, y: 36).prefix(3)), [255, 255, 255], "deselected one is untouched")
        XCTAssertEqual(Array(try pixel(output, x: 60, y: 5).prefix(3)), [255, 255, 255])
        XCTAssertEqual(appliedCount, 1)
        XCTAssertFalse(suggestions.isShowing, "suggestions are cleared")
        XCTAssertEqual(document.objects.count, 1)
        document.undo()
        XCTAssertTrue(document.objects.isEmpty, "blackout is one undo step")
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
        let image = try whiteImage()
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

        XCTAssertEqual(Array(try pixel(output, x: 25, y: 16).prefix(3)), [0, 0, 0], "found region is black")
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
        XCTAssertEqual(document.objects.count, 1, "the pending suggestion became a black bar, not discarded")
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
