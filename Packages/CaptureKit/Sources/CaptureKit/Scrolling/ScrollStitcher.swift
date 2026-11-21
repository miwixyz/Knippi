// Packages/CaptureKit/Sources/CaptureKit/Scrolling/ScrollStitcher.swift
import CoreGraphics
import Foundation

public enum StitchResult: Sendable {
    case stitched(yOffset: Int)
    case noChange
    case reversedScroll
    case alignmentFailed
}

/// Incrementally stitches captured frames into a single tall image.
/// The offset is detected externally (by ScrollCaptureController via Vision)
/// and passed in. This class only handles the pixel compositing.
///
/// Pixels live in one growing buffer, so a stitch only writes the new rows
/// (linear in the page height overall). The full image is built once, on
/// `mergedImage`; while scrolling, `previewImage` is a small copy kept in step.
///
/// Rows inside a sticky footer are never appended while scrolling; the most
/// recent frame's footer is added once at the bottom of `mergedImage`.
public final class ScrollStitcher: @unchecked Sendable {
    /// Width of the live preview in pixels.
    static let previewWidth = 240

    fileprivate static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue

    private var body = Canvas()
    private var preview = Canvas()
    private var previewScale = 1.0
    private var lastFrame: CGImage?
    private var footerHeight = 0
    private(set) var totalHeight: Int = 0

    public init() {}

    /// The stitched page including the sticky footer, if any.
    var mergedImage: CGImage? {
        guard body.rows > 0 else { return nil }
        var page = body
        if footerHeight > 0, let lastFrame,
           let footer = lastFrame.cropping(to: CGRect(
               x: 0, y: lastFrame.height - footerHeight,
               width: lastFrame.width, height: footerHeight
           )) {
            _ = page.append(footer, rows: footerHeight, quality: .none)
        }
        return page.makeImage()
    }

    /// A small copy of the stitched body for the live preview.
    var previewImage: CGImage? {
        preview.makeImage()
    }

    public func setInitialFrame(_ frame: CGImage) {
        let space = Self.bitmapColorSpace(for: frame)
        body = Canvas(width: frame.width, colorSpace: space)
        body.reserve(rows: frame.height * 4)
        let previewWidth = min(Self.previewWidth, frame.width)
        previewScale = Double(previewWidth) / Double(max(frame.width, 1))
        preview = Canvas(width: previewWidth, colorSpace: space)
        footerHeight = 0
        lastFrame = frame
        _ = appendBody(frame)
        totalHeight = frame.height
    }

    /// Excludes the bottom `height` rows of every frame from the stitched body.
    func setFooterHeight(_ height: Int) {
        guard height > 0, height < body.rows else { return }
        footerHeight = height
        body.removeLast(rows: height)
        preview.removeLast(rows: preview.rows - previewRows(forBodyRows: body.rows))
    }

    /// Stitch a new frame that is scrolled `detectedOffset` pixel rows further down.
    public func stitch(newFrame: CGImage, detectedOffset: Int) -> StitchResult {
        guard body.rows > 0 else {
            setInitialFrame(newFrame)
            return .stitched(yOffset: 0)
        }
        guard detectedOffset > 0 else { return detectedOffset < 0 ? .reversedScroll : .noChange }

        let contentBottom = newFrame.height - footerHeight
        guard detectedOffset < contentBottom,
              let newRows = newFrame.cropping(to: CGRect(
                  x: 0, y: contentBottom - detectedOffset,
                  width: newFrame.width, height: detectedOffset
              )),
              newRows.height == detectedOffset,
              appendBody(newRows) else {
            return .alignmentFailed
        }

        lastFrame = newFrame
        totalHeight = body.rows + footerHeight
        return .stitched(yOffset: detectedOffset)
    }

    private func appendBody(_ strip: CGImage) -> Bool {
        guard body.append(strip, rows: strip.height, quality: .none) else { return false }
        let previewRows = previewRows(forBodyRows: body.rows) - preview.rows
        if previewRows > 0 {
            _ = preview.append(strip, rows: previewRows, quality: .medium)
        }
        return true
    }

    private func previewRows(forBodyRows rows: Int) -> Int {
        Int((Double(rows) * previewScale).rounded())
    }

    /// The frame's colour space if a bitmap context can draw in it, else sRGB.
    private static func bitmapColorSpace(for frame: CGImage) -> CGColorSpace {
        if let space = frame.colorSpace, space.model == .rgb, space.supportsOutput {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}

/// A growable 32-bit BGRA bitmap, filled top to bottom.
private struct Canvas {
    var width = 0
    var colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    private(set) var pixels = Data()

    init() {}

    init(width: Int, colorSpace: CGColorSpace) {
        self.width = width
        self.colorSpace = colorSpace
    }

    var bytesPerRow: Int { width * 4 }
    var rows: Int { bytesPerRow > 0 ? pixels.count / bytesPerRow : 0 }

    mutating func reserve(rows: Int) {
        pixels.reserveCapacity(rows * bytesPerRow)
    }

    mutating func removeLast(rows count: Int) {
        guard count > 0 else { return }
        pixels.count -= min(count, rows) * bytesPerRow
    }

    /// Draws `strip` scaled to `rows` × `width` below the current rows.
    mutating func append(_ strip: CGImage, rows count: Int, quality: CGInterpolationQuality) -> Bool {
        guard count > 0, width > 0 else { return false }
        let start = pixels.count
        pixels.count += count * bytesPerRow
        let (width, bytesPerRow, colorSpace) = (width, bytesPerRow, colorSpace)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(
                      data: base + start, width: width, height: count,
                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                      space: colorSpace, bitmapInfo: ScrollStitcher.bitmapInfo
                  ) else { return false }
            ctx.interpolationQuality = quality
            ctx.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: count))
            return true
        }
        if !drawn { pixels.count = start }
        return drawn
    }

    func makeImage() -> CGImage? {
        guard rows > 0, let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: ScrollStitcher.bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
