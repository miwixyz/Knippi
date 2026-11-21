import XCTest
import SharedKit
@testable import Knippi

/// Phase 2 complete: scrolling capture since 0.2.0, screen recording since
/// 0.3.0 (Knippi spec §2). Nothing is hidden any more.
final class PhaseOneVisibilityTests: XCTestCase {
    func testNoFeatureIsHidden() {
        XCTAssertTrue(FeatureFlags.screenRecording)
        XCTAssertTrue(FeatureFlags.scrollingCapture)
    }

    func testAutomationSheetShowsRecordingCommands() {
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

        XCTAssertEqual(sections.map(\.id), ["screenshots", "recording"])
        XCTAssertEqual(sections.last?.items.map(\.id), ["record", "record-fullscreen"])
    }

    func testPreferencesSidebarShowsRecordingTab() {
        XCTAssertTrue(PreferencesTab.visibleCases.contains(.recording))
        XCTAssertEqual(PreferencesTab.visibleCases.count, PreferencesTab.allCases.count)
    }
}
