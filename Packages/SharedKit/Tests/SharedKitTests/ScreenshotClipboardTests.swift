import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import SharedKit

@Suite("ScreenshotClipboard")
struct ScreenshotClipboardTests {
    @Test("Image content copies image data without materializing a file")
    func imageContentCopiesImageWithoutMaterializingFile() throws {
        let pasteboard = makePasteboard()
        var requestedFileURL = false

        let copied = ScreenshotClipboard.copy(
            try makeImage(),
            content: .image,
            imageFormat: .png,
            pasteboard: pasteboard
        ) {
            requestedFileURL = true
            return URL(fileURLWithPath: "/tmp/unused.png")
        }

        #expect(copied)
        #expect(!requestedFileURL)
        #expect(pasteboard.data(forType: .png) != nil)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("File path content copies a readable absolute path as text")
    func filePathContentCopiesReadableAbsolutePath() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotClipboardTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Screenshot.png")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)
        let pasteboard = makePasteboard()

        let copied = ScreenshotClipboard.copy(
            try makeImage(),
            content: .filePath,
            imageFormat: .png,
            pasteboard: pasteboard
        ) {
            fileURL
        }

        #expect(copied)
        #expect(pasteboard.string(forType: .string) == fileURL.path)
        #expect(FileManager.default.isReadableFile(atPath: fileURL.path))
        #expect(pasteboard.data(forType: .png) == nil)
    }

    @Test("Unreadable file path leaves existing clipboard content unchanged")
    func unreadableFilePathLeavesClipboardUnchanged() throws {
        let pasteboard = makePasteboard()
        pasteboard.setString("keep me", forType: .string)
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Missing.png")

        let copied = ScreenshotClipboard.copy(
            try makeImage(),
            content: .filePath,
            imageFormat: .png,
            pasteboard: pasteboard
        ) {
            missingURL
        }

        #expect(!copied)
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test("PNG clipboard keeps transparent pixels of a window capture")
    func pngClipboardKeepsAlpha() throws {
        let pasteboard = makePasteboard()
        #expect(ScreenshotClipboard.copy(
            try makeTransparentImage(), content: .image, imageFormat: .png, pasteboard: pasteboard
        ) { URL(fileURLWithPath: "/tmp/unused.png") })

        let data = try #require(pasteboard.data(forType: .png))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.hasAlpha)
        #expect(try #require(rep.colorAt(x: 0, y: 0)).alphaComponent < 0.01)
        #expect(try #require(rep.colorAt(x: 5, y: 5)).alphaComponent > 0.99)
    }

    @Test("JPEG clipboard also carries PNG with alpha when the image is transparent")
    func jpegClipboardAddsPNGForTransparentImages() throws {
        let pasteboard = makePasteboard()
        #expect(ScreenshotClipboard.copy(
            try makeTransparentImage(), content: .image, imageFormat: .jpeg, pasteboard: pasteboard
        ) { URL(fileURLWithPath: "/tmp/unused.png") })

        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) != nil)
        let data = try #require(pasteboard.data(forType: .png))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(try #require(rep.colorAt(x: 0, y: 0)).alphaComponent < 0.01)
    }

    @Test("JPEG clipboard of an opaque image stays JPEG only")
    func jpegClipboardOfOpaqueImageStaysJPEG() throws {
        let pasteboard = makePasteboard()
        #expect(ScreenshotClipboard.copy(
            try makeImage(), content: .image, imageFormat: .jpeg, pasteboard: pasteboard
        ) { URL(fileURLWithPath: "/tmp/unused.png") })
        #expect(pasteboard.data(forType: .png) == nil)
    }

    private func makeTransparentImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 3, y: 3, width: 4, height: 4))
        return try #require(context.makeImage())
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ScreenshotClipboardTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 4,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return try #require(context.makeImage())
    }
}
