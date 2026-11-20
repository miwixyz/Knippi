import AppKit
import CaptureKit
import SharedKit
import XCTest
@testable import Knippi

@MainActor
final class ScreenshotClipboardContentTests: XCTestCase {
    func testQuickAccessSaveFailureKeepsPreviewAvailableForRetry() throws {
        let settings = makeSettings()
        settings.quickAccessAutoClose = false
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-save-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }
        let blockedDirectory = exportRoot.appendingPathComponent("blocked")
        try Data([1]).write(to: blockedDirectory)
        settings.setExportLocation(blockedDirectory)
        let coordinator = CaptureCoordinator(settings: settings)
        let window = coordinator.showQuickAccess(
            for: try makeCaptureResult(), entryID: UUID(), autoUpload: false,
            pasteboard: makePasteboard()
        )
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        window.onSave?()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.ignoresMouseEvents)

        settings.setExportLocation(exportRoot)
        window.onSave?()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(window.isVisible)
        let files = try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.pathExtension == "png" })
    }

    func testFilePathContentCopiesReadableManagedFileWithoutPreview() throws {
        let settings = makeSettings()
        settings.screenshotClipboardContent = .filePath
        settings.screenshotOutputFormat = .png
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        XCTAssertTrue(coordinator.copyScreenshotToClipboard(
            try makeCaptureResult(),
            entryID: UUID(),
            pasteboard: pasteboard
        ))

        let path = try XCTUnwrap(pasteboard.string(forType: .string))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertEqual((path as NSString).pathExtension, "png")
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: path))
    }

    func testFilePathContentPrefersSuccessfulAutoSaveOutput() throws {
        let settings = makeSettings()
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let savedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-autosave-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: savedURL)
        defer { try? FileManager.default.removeItem(at: savedURL) }

        XCTAssertTrue(coordinator.copyScreenshotToClipboard(
            try makeCaptureResult(),
            entryID: UUID(),
            preferredFileURL: savedURL,
            pasteboard: pasteboard
        ))

        XCTAssertEqual(pasteboard.string(forType: .string), savedURL.path)
    }

    func testDefaultPostCaptureCopiesFilePathWhenPreviewIsDisabled() throws {
        let settings = makeSettings()
        settings.screenshotShowPreview = false
        settings.screenshotAutoCopy = true
        settings.screenshotAutoSave = false
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        coordinator.applyDefaultPostCaptureActions(
            try makeCaptureResult(),
            entryID: UUID(),
            pasteboard: pasteboard
        )

        let path = try XCTUnwrap(pasteboard.string(forType: .string))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: path))
    }

    func testDefaultPostCaptureCopiesAutoSaveOutputPathWithoutDuplicateTemporaryFile() throws {
        let settings = makeSettings()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardAutoSaveTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        settings.setExportLocation(exportDirectory)
        settings.screenshotShowPreview = false
        settings.screenshotAutoCopy = true
        settings.screenshotAutoSave = true
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        coordinator.applyDefaultPostCaptureActions(
            try makeCaptureResult(),
            entryID: UUID(),
            pasteboard: pasteboard
        )

        let copiedPath = try XCTUnwrap(pasteboard.string(forType: .string))
        defer {
            if !copiedPath.hasPrefix(exportDirectory.path) {
                try? FileManager.default.removeItem(atPath: copiedPath)
            }
        }
        let savedFiles = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(savedFiles.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: copiedPath).resolvingSymlinksInPath(),
            savedFiles[0].resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: copiedPath))
    }

    func testQuickAccessCopyReusesAutoSaveOutputPath() throws {
        let settings = makeSettings()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardQuickAccessTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        settings.setExportLocation(exportDirectory)
        settings.screenshotAutoCopy = false
        settings.screenshotAutoSave = true
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let result = try makeCaptureResult()
        let entryID = UUID()

        let savedFileURL = try XCTUnwrap(coordinator.applyDefaultPostCaptureActions(
            result,
            entryID: entryID,
            pasteboard: pasteboard
        ))
        let window = coordinator.showQuickAccess(
            for: result,
            entryID: entryID,
            autoUpload: false,
            preferredFileURL: savedFileURL,
            pasteboard: pasteboard
        )
        window.onCopy?()

        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(pasteboard.string(forType: .string)))
                .resolvingSymlinksInPath(),
            savedFileURL.resolvingSymlinksInPath()
        )
    }

    func testQuickAccessSaveReplacesManagedTemporaryPathWithSavedPath() throws {
        let settings = makeSettings()
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardQuickAccessSaveTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        settings.setExportLocation(exportDirectory)
        settings.screenshotAutoCopy = true
        settings.screenshotAutoSave = false
        settings.screenshotClipboardContent = .filePath
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()
        let result = try makeCaptureResult()
        let entryID = UUID()

        coordinator.applyDefaultPostCaptureActions(
            result,
            entryID: entryID,
            pasteboard: pasteboard
        )
        let temporaryPath = try XCTUnwrap(pasteboard.string(forType: .string))
        defer { try? FileManager.default.removeItem(atPath: temporaryPath) }

        let window = coordinator.showQuickAccess(
            for: result,
            entryID: entryID,
            autoUpload: false,
            pasteboard: pasteboard
        )
        window.onSave?()

        let savedPath = try XCTUnwrap(pasteboard.string(forType: .string))
        let savedFiles = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertNotEqual(
            URL(fileURLWithPath: savedPath).resolvingSymlinksInPath(),
            URL(fileURLWithPath: temporaryPath).resolvingSymlinksInPath()
        )
        XCTAssertEqual(savedFiles.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: savedPath).resolvingSymlinksInPath(),
            savedFiles[0].resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: savedPath))
    }

    func testSilentModeCopiesAndSavesIgnoringAutoToggles() throws {
        let settings = makeSettings()
        settings.screenshotAutoCopy = false
        settings.screenshotAutoSave = false
        settings.screenshotOutputFormat = .png
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-silent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: exportRoot) }
        settings.setExportLocation(exportRoot)
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        let result = coordinator.applySilentPostCaptureActions(
            try makeCaptureResult(), entryID: UUID(), pasteboard: pasteboard
        )

        let url = try result.get()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Knippi 1970-01-01 um "))
        XCTAssertNotNil(pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff))
    }

    func testSilentModeSaveFailureKeepsImageOnClipboard() throws {
        let settings = makeSettings()
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("knippi-silent-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }
        let blocked = exportRoot.appendingPathComponent("blocked")
        try Data([1]).write(to: blocked)
        settings.setExportLocation(blocked)
        let coordinator = CaptureCoordinator(settings: settings)
        let pasteboard = makePasteboard()

        let result = coordinator.applySilentPostCaptureActions(
            try makeCaptureResult(), entryID: UUID(), pasteboard: pasteboard
        )

        guard case .failure = result else { return XCTFail("expected save failure") }
        XCTAssertNotNil(pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff))
    }

    private func makeSettings() -> AppSettings {
        let suite = "ScreenshotClipboardContentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ScreenshotClipboardContentTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeCaptureResult() throws -> CaptureResult {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 6,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return CaptureResult(
            image: try XCTUnwrap(context.makeImage()),
            mode: .area,
            captureRect: CGRect(x: 0, y: 0, width: 8, height: 6),
            windowName: "Terminal",
            appName: "Agent",
            timestamp: Date(timeIntervalSince1970: 1_800),
            displayID: 1
        )
    }
}
