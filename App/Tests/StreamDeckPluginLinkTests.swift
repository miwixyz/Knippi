import XCTest
@testable import Knippi

/// Menu item "Get Stream Deck Plugin…": the link must stay a direct download of the plugin file from
/// this project's latest GitHub release (the file name is the release asset's name, see `scripts/release.sh`).
@MainActor
final class StreamDeckPluginLinkTests: XCTestCase {
    func testLinkPointsToTheLatestReleaseAsset() {
        let url = MenuBarController.streamDeckPluginURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/miwixyz/Knippi/releases/latest/download/Knippi.streamDeckPlugin")
        XCTAssertNil(url.query)
    }

    func testAssetNameMatchesWhatTheReleaseScriptUploads() throws {
        // release.sh attaches the plugin as dist/streamdeck/Knippi.streamDeckPlugin.
        let name = MenuBarController.streamDeckPluginURL.lastPathComponent
        XCTAssertEqual(name, "Knippi.streamDeckPlugin")
        XCTAssertTrue(name.hasSuffix(".streamDeckPlugin"))
    }
}
