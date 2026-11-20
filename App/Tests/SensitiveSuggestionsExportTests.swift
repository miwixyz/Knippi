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
}
