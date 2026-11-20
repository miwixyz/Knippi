import SharedKit
import XCTest
@testable import Knippi

final class WindowCaptureTreatmentTests: XCTestCase {
    func testShadowOffCapturesPlainWindowWhateverTheBackground() {
        for background in WindowCaptureBackground.allCases {
            XCTAssertEqual(
                CaptureCoordinator.windowCaptureTreatment(captureWindowShadow: false, background: background),
                .plain
            )
        }
    }

    func testTransparentShadowUsesNativeShadow() {
        XCTAssertEqual(
            CaptureCoordinator.windowCaptureTreatment(captureWindowShadow: true, background: .transparentShadow),
            .nativeShadow
        )
    }

    func testFrostedGlassKeepsPreviousBehaviour() {
        XCTAssertEqual(
            CaptureCoordinator.windowCaptureTreatment(captureWindowShadow: true, background: .frostedGlass),
            .frostedGlass
        )
    }
}
