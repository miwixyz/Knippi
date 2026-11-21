import XCTest
import SharedKit
@testable import Knippi

/// Screen recording stays hidden; scrolling capture is on since 0.2.0 (Knippi spec §2).
final class PhaseOneVisibilityTests: XCTestCase {
    func testOnlyScreenRecordingIsHidden() {
        XCTAssertFalse(FeatureFlags.screenRecording)
        XCTAssertTrue(FeatureFlags.scrollingCapture)
    }

    func testAutomationSheetDropsHiddenCommandsAndEmptySections() {
        let sections = AutomationCommandSection.visible([
            AutomationCommandSection(id: "screenshots", title: "Screenshots", items: [
                AutomationCommandItem(id: "area", name: "Capture Area", urlString: "knippi://grab/area"),
                AutomationCommandItem(id: "scrolling", name: "Scrolling Capture", urlString: "knippi://grab/scrolling"),
            ]),
            AutomationCommandSection(id: "recording", title: "Recording", items: [
                AutomationCommandItem(id: "record", name: "Record Area", urlString: "knippi://grab/record"),
                AutomationCommandItem(id: "record-fullscreen", name: "Record Full Screen", urlString: "knippi://grab/record-fullscreen"),
            ]),
        ])

        XCTAssertEqual(sections.map(\.id), ["screenshots"])
        XCTAssertEqual(sections.first?.items.map(\.id), ["area", "scrolling"])
    }

    func testPreferencesSidebarHidesRecordingTab() {
        XCTAssertFalse(PreferencesTab.visibleCases.contains(.recording))
        XCTAssertEqual(PreferencesTab.visibleCases.count, PreferencesTab.allCases.count - 1)
    }
}
