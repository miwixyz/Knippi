import XCTest
import SharedKit
@testable import Knippi

/// Phase 1 hides screen recording and scrolling capture (Knippi spec §2).
final class PhaseOneVisibilityTests: XCTestCase {
    func testFlagsAreOffInPhaseOne() {
        XCTAssertFalse(FeatureFlags.screenRecording)
        XCTAssertFalse(FeatureFlags.scrollingCapture)
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
        XCTAssertEqual(sections.first?.items.map(\.id), ["area"])
    }

    func testPreferencesSidebarHidesRecordingTab() {
        XCTAssertFalse(PreferencesTab.visibleCases.contains(.recording))
        XCTAssertEqual(PreferencesTab.visibleCases.count, PreferencesTab.allCases.count - 1)
    }
}
