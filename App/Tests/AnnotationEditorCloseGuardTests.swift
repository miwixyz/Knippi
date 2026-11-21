import AppKit
import SharedKit
import XCTest
@testable import Knippi

@MainActor
final class AnnotationEditorCloseGuardTests: XCTestCase {
    func testCleanDocumentClosesWithoutPrompt() {
        var confirmCount = 0
        let shouldClose = AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: false,
            confirmDiscard: {
                confirmCount += 1
                return true
            }
        )
        XCTAssertTrue(shouldClose)
        XCTAssertEqual(confirmCount, 0)
    }

    func testDirtyDocumentClosesWhenConfirmed() {
        var confirmCount = 0
        let shouldClose = AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: true,
            confirmDiscard: {
                confirmCount += 1
                return true
            }
        )
        XCTAssertTrue(shouldClose)
        XCTAssertEqual(confirmCount, 1)
    }

    func testDirtyDocumentStaysOpenWhenDeclined() {
        let shouldClose = AnnotationEditorCloseGuard.shouldClose(
            hasUnsavedChanges: true,
            confirmDiscard: { false }
        )
        XCTAssertFalse(shouldClose)
    }

    /// Audit A14 (21.11.): text typed into the inline editor but not yet committed
    /// was lost on close without a prompt.
    func testOpenTextEditorWithTypedTextCountsAsPending() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let container = NSView(frame: root.bounds)
        root.addSubview(container)
        XCTAssertFalse(AnnotationEditorCloseGuard.hasPendingText(in: root))

        let editor = AnnotationTextEditor(frame: .zero)
        container.addSubview(editor)
        editor.beginEditing(initialText: "   ")
        XCTAssertFalse(AnnotationEditorCloseGuard.hasPendingText(in: root))

        editor.beginEditing(initialText: "Hallo")
        XCTAssertTrue(AnnotationEditorCloseGuard.hasPendingText(in: root))
        XCTAssertFalse(AnnotationEditorCloseGuard.hasPendingText(in: nil))
    }

    func testCloseRequestWithPendingTextAsksFirst() {
        let window = AnnotationEditorWindow(
            image: Self.makeImage(),
            screenshotOutput: ScreenshotOutputOptions(format: .png, quality: 0.85),
            screenshotFilenameTemplate: "Screenshot",
            onSave: { _ in true },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }
        var asked = 0
        window.confirmDiscard = { asked += 1; return false }
        let editor = AnnotationTextEditor(frame: .zero)
        window.contentView?.addSubview(editor)
        editor.beginEditing(initialText: "Hallo")

        XCTAssertFalse(window.windowShouldClose(window))
        XCTAssertEqual(asked, 1)
    }

    private static func makeImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    func testSystemAlertSupportsRepeatedAreaCapturesWithoutBecomingModalAgain() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .knippiCaptureDidFreezeDesktop, object: nil)
        }

        let shouldClose = AnnotationEditorCloseGuard.presentDiscardAlert(above: nil)

        XCTAssertFalse(shouldClose)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isSuspendedAlertVisibleForTesting)

        NotificationCenter.default.post(name: .knippiCaptureDidEnd, object: nil)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isModelessAlertVisibleForTesting)

        // A second close request must reuse the restored modeless alert rather
        // than presenting a second modal discard dialog on top of it.
        XCTAssertFalse(AnnotationEditorCloseGuard.presentDiscardAlert(above: nil))
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isModelessAlertVisibleForTesting)

        NotificationCenter.default.post(name: .knippiCaptureDidFreezeDesktop, object: nil)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isSuspendedAlertVisibleForTesting)

        NotificationCenter.default.post(name: .knippiCaptureDidEnd, object: nil)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(AnnotationEditorCloseGuard.isModelessAlertVisibleForTesting)

        AnnotationEditorCloseGuard.dismissSuspendedAlertForTesting()
        XCTAssertNil(NSApp.modalWindow)
    }
}
