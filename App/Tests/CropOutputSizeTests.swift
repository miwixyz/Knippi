import CoreGraphics
import XCTest
@testable import Knippi

/// Audit A7 (21.11.): with "Resize output" on, the width/height drafts did not follow a
/// changed crop or a rotate (distorted output despite the ratio lock), and any size was
/// accepted (100000×100000 allocated a ~40 GB bitmap).
final class CropOutputSizeTests: XCTestCase {
    private let crop = CGSize(width: 1600, height: 1200)

    func testLockedRatioDerivesHeightFromWidth() {
        let size = CropEditorView.outputSize(width: 800, height: 123, cropSize: crop, aspectLocked: true, driving: .width)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    func testLockedRatioDerivesWidthFromHeight() {
        let size = CropEditorView.outputSize(width: 1, height: 300, cropSize: crop, aspectLocked: true, driving: .height)
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 300)
    }

    func testChangedCropReDerivesHeightForTheSameWidth() {
        // Crop went from 4:3 to 1:2 while the drafts still say 800×600.
        let size = CropEditorView.outputSize(
            width: 800, height: 600, cropSize: CGSize(width: 500, height: 1000), aspectLocked: true, driving: .width
        )
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 1600)
    }

    func testUnlockedRatioKeepsBothValues() {
        let size = CropEditorView.outputSize(width: 800, height: 123, cropSize: crop, aspectLocked: false, driving: .width)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 123)
    }

    func testHugeSizeIsCappedKeepingTheRatio() {
        let size = CropEditorView.outputSize(width: 100_000, height: 100_000, cropSize: crop, aspectLocked: true, driving: .width)
        XCTAssertEqual(size.width, CropEditorView.maxOutputSide)
        XCTAssertLessThanOrEqual(size.height, CropEditorView.maxOutputSide)
        XCTAssertEqual(Double(size.width) / Double(size.height), 4.0 / 3.0, accuracy: 0.01)

        let unlocked = CropEditorView.outputSize(width: 100_000, height: 100_000, cropSize: crop, aspectLocked: false, driving: .width)
        XCTAssertEqual(unlocked.width, CropEditorView.maxOutputSide)
        XCTAssertEqual(unlocked.height, CropEditorView.maxOutputSide)
    }

    func testExtremeValuesDoNotTrap() {
        let size = CropEditorView.outputSize(
            width: Int.max, height: 1, cropSize: CGSize(width: 1, height: 10_000), aspectLocked: true, driving: .width
        )
        XCTAssertLessThanOrEqual(max(size.width, size.height), CropEditorView.maxOutputSide)
        XCTAssertGreaterThanOrEqual(min(size.width, size.height), 1)
    }

    func testMissingDraftFallsBackToCropSize() {
        let size = CropEditorView.outputSize(width: nil, height: nil, cropSize: crop, aspectLocked: false, driving: .width)
        XCTAssertEqual(size.width, 1600)
        XCTAssertEqual(size.height, 1200)
    }
}
