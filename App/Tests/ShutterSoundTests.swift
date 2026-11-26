import AppKit
import XCTest

/// Knippis eigener Auslöser-Ton „Tock“ muss im App-Bundle liegen und abspielbar sein,
/// sonst fällt die App still auf den macOS-Systemton zurück.
final class ShutterSoundTests: XCTestCase {
    func testTockSoundIsBundledAndPlayable() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Ausloeser-Tock", withExtension: "caf"))
        let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: true))
        XCTAssertGreaterThan(sound.duration, 0.05)
        XCTAssertLessThan(sound.duration, 0.3)
    }
}
