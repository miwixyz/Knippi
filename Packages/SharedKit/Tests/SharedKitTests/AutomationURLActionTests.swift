import Foundation
import Testing
@testable import SharedKit

@Suite("Automation URL actions")
struct AutomationURLActionTests {
    @Test("Supported URLs map to capture actions")
    func supportedURLs() {
        let cases: [(String, AutomationURLAction)] = [
            ("knippi://grab/area", .captureArea),
            ("knippi://grab/fullscreen", .captureFullscreen),
            ("knippi://grab/window", .captureWindow),
            ("knippi://grab/all-in-one", .captureAllInOne),
            ("knippi://grab/scrolling", .captureScrolling),
            ("knippi://grab/self-timer", .captureSelfTimer),
            ("knippi://grab/last-area", .captureLastArea),
            ("knippi://grab/clipboard", .captureAreaToClipboard),
            ("knippi://grab/area-to-clipboard", .captureAreaToClipboard),
            ("knippi://grab/share", .captureAreaAndShare),
            ("knippi://grab/area-and-share", .captureAreaAndShare),
            ("knippi://grab/annotate", .captureAreaAndAnnotate),
            ("knippi://grab/area-and-annotate", .captureAreaAndAnnotate),
            ("knippi://grab/area-and-pin", .captureAreaAndPin),
            ("knippi://grab/color", .pickColor),
            ("knippi://grab/pin", .pinFromClipboard),
            ("knippi://grab/pin-from-clipboard", .pinFromClipboard),
            ("knippi://grab/edit-clipboard", .editClipboardImage),
            ("knippi://grab/edit-clipboard-image", .editClipboardImage),
            ("knippi://grab/open-image", .openImageFile),
            ("knippi://grab/open-image-file", .openImageFile),
            ("knippi://grab/ocr", .captureOCR),
            ("knippi://grab/text", .captureOCR),
            ("knippi://grab/capture-text", .captureOCR),
            ("knippi://grab/record", .recordArea),
            ("knippi://grab/record-area", .recordArea),
            ("knippi://grab/record-screen", .recordArea),
            ("knippi://grab/record-fullscreen", .recordFullscreen),
            ("knippi://grab/record-full-screen", .recordFullscreen),
            ("knippi://grab/hide-desktop-icons", .hideDesktopIcons),
            ("knippi://grab/show-desktop-icons", .showDesktopIcons),
            ("knippi://grab/toggle-desktop-icons", .toggleDesktopIcons),
            ("knippi://grab/preferences", .openPreferences),
            ("knippi://grab/settings", .openPreferences),
            ("KNIPPI://GRAB/area", .captureArea),
            ("KNIPPI://GRAB/ocr", .captureOCR),
            ("KNIPPI://GRAB/record", .recordArea),
        ]

        for (rawURL, expected) in cases {
            #expect(AutomationURLAction(url: URL(string: rawURL)!) == expected)
        }
    }

    @Test("Unsupported or parameterized URLs are rejected")
    func unsupportedURLs() {
        let urls = [
            "https://grab/area",
            "knippi://capture/area",
            "knippi://grab",
            "knippi://grab/AREA",
            "knippi://grab/RECORD",
            "knippi://grab/unknown",
            "knippi://grab/nonexistent",
            "knippi://grab//area",
            "knippi://grab/area/",
            "knippi://grab/%61rea",
            "knippi://grab/area/extra",
            "knippi://grab/area?then=save",
            "knippi://grab/area#fragment",
            "knippi://user@grab/area",
            "knippi://grab:123/area",
        ]

        for rawURL in urls {
            #expect(AutomationURLAction(url: URL(string: rawURL)!) == nil)
        }
    }

    @Test("Request buffer retains only the first action until ready")
    func retainsFirstAction() {
        var buffer = AutomationURLRequestBuffer()
        buffer.enqueue(.captureArea)
        buffer.enqueue(.captureWindow)

        #expect(buffer.takeIfReady(
            coordinatorIsReady: false,
            captureSelectionIsActive: false
        ) == nil)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == .captureArea)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == nil)
    }

    @Test("Busy selection consumes and discards the pending action")
    func busySelectionDropsAction() {
        var buffer = AutomationURLRequestBuffer()
        buffer.enqueue(.captureFullscreen)

        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: true
        ) == nil)
        #expect(buffer.takeIfReady(
            coordinatorIsReady: true,
            captureSelectionIsActive: false
        ) == nil)
    }
}
