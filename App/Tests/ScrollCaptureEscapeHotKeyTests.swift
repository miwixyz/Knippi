import XCTest
@testable import Knippi

@MainActor
final class ScrollCaptureEscapeHotKeyTests: XCTestCase {
    func testEscapeRunsActionOnlyWhileRegistered() throws {
        var presses = 0
        let hotKey = try XCTUnwrap(ScrollCaptureEscapeHotKey { presses += 1 })
        XCTAssertEqual(ScrollCaptureEscapeHotKey.registeredCount, 1)

        // Same path as a real press: our signature, our id.
        XCTAssertTrue(ScrollCaptureEscapeHotKey.handlePress(signature: 0x4B_6E_45_73, id: idOf(hotKey)))
        XCTAssertEqual(presses, 1)

        hotKey.unregister()
        XCTAssertEqual(ScrollCaptureEscapeHotKey.registeredCount, 0)
        XCTAssertFalse(ScrollCaptureEscapeHotKey.handlePress(signature: 0x4B_6E_45_73, id: idOf(hotKey)))
        XCTAssertEqual(presses, 1)
    }

    func testOtherHotKeysAreNotSwallowed() {
        XCTAssertFalse(ScrollCaptureEscapeHotKey.handlePress(signature: 0x4B_53_68_74, id: 1))
    }

    private func idOf(_ hotKey: ScrollCaptureEscapeHotKey) -> UInt32 {
        Mirror(reflecting: hotKey).children.first { $0.label == "id" }?.value as? UInt32 ?? 0
    }
}
