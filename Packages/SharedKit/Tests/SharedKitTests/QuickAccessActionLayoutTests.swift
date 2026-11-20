import Testing
@testable import SharedKit

@Suite("Quick Access action layout")
struct QuickAccessActionLayoutTests {
    @Test("Core workflow remains one click without cloud sharing")
    func visibleActionsWithoutSharing() {
        #expect(QuickAccessActionLayout.visibleActions(sharingAvailable: false) == [
            .drag,
            .copy,
            .save,
            .annotate,
            .findSensitive,
            .pin,
        ])
    }

    @Test("Find Sensitive Data is one click, never in overflow")
    func findSensitiveIsVisible() {
        for sharing in [false, true] {
            #expect(QuickAccessActionLayout.visibleActions(sharingAvailable: sharing).contains(.findSensitive))
        }
        #expect(!QuickAccessActionLayout.overflowActions.contains(.findSensitive))
    }

    @Test("Cloud sharing adds Upload while intelligence actions stay in overflow")
    func visibleActionsWithSharing() {
        #expect(QuickAccessActionLayout.visibleActions(sharingAvailable: true) == [
            .drag,
            .copy,
            .save,
            .upload,
            .annotate,
            .findSensitive,
            .pin,
        ])
        #expect(QuickAccessActionLayout.overflowActions == [.ocr])
    }
}
