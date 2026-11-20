import CaptureKit
import Foundation
@preconcurrency import ScreenCaptureKit
import XCTest
@testable import Knippi

final class CapturePermissionGateTests: XCTestCase {
    // MARK: - CaptureRoute

    func testSyncShortcutOnlyWithPermissionAndSymbol() {
        XCTAssertEqual(CaptureRoute.choose(preflight: true, syncAvailable: true), .sync)
    }

    /// Without permission CGDisplayCreateImage returns a wallpaper-only image
    /// (measured 2026-11-20). It must never be used then.
    func testNoPermissionGoesToScreenCaptureKit() {
        XCTAssertEqual(CaptureRoute.choose(preflight: false, syncAvailable: true), .screenCaptureKit)
    }

    func testMissingSymbolGoesToScreenCaptureKit() {
        XCTAssertEqual(CaptureRoute.choose(preflight: true, syncAvailable: false), .screenCaptureKit)
        XCTAssertEqual(CaptureRoute.choose(preflight: false, syncAvailable: false), .screenCaptureKit)
    }

    // MARK: - CaptureErrorPresentation

    func testUserDeclinedStreamErrorIsPermissionMissing() {
        let error = NSError(domain: SCStreamErrorDomain, code: -3801)
        XCTAssertEqual(CaptureErrorPresentation.forError(error), .permissionMissing)
    }

    func testTypedUserDeclinedIsPermissionMissing() {
        let error = SCStreamError(.userDeclined)
        XCTAssertEqual(CaptureErrorPresentation.forError(error), .permissionMissing)
    }

    func testCaptureKitPermissionDeniedIsPermissionMissing() {
        XCTAssertEqual(
            CaptureErrorPresentation.forError(CaptureError.capturePermissionDenied),
            .permissionMissing
        )
    }

    func testOtherStreamErrorIsGeneric() {
        let error = NSError(domain: SCStreamErrorDomain, code: -3802, userInfo: [
            NSLocalizedDescriptionKey: "boom",
        ])
        XCTAssertEqual(CaptureErrorPresentation.forError(error), .generic("boom"))
    }

    func testSameCodeOtherDomainIsGeneric() {
        let error = NSError(domain: "other", code: -3801, userInfo: [
            NSLocalizedDescriptionKey: "x",
        ])
        XCTAssertEqual(CaptureErrorPresentation.forError(error), .generic("x"))
    }
}
