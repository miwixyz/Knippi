// Packages/CaptureKit/Sources/CaptureKit/Scrolling/HeaderDetector.swift
import CoreGraphics

/// Detects sticky/frozen headers at the top of captured frames by comparing
/// pixel rows between two consecutive frames. Rows that are identical in
/// both frames are part of a sticky header and should be excluded from stitching.
enum HeaderDetector {
    /// Maximum percentage of image height to scan for headers.
    private static let maxScanPercent = 0.20
    /// Number of columns to sample per row for comparison.
    private static let sampleColumns = 20
    /// Per-pixel difference tolerance (accounts for sub-pixel rendering differences).
    private static let tolerance: Int = 2

    /// Sticky header and footer heights of two consecutive frames: the
    /// number of identical pixel rows at the top and at the bottom. Each
    /// frame's bytes are copied once for both scans (audit C13, 21.11.).
    static func detectFixedRows(frame1: CGImage, frame2: CGImage) -> (header: Int, footer: Int) {
        guard let data1 = frame1.dataProvider?.data,
              let data2 = frame2.dataProvider?.data else { return (0, 0) }
        return (
            unchangedRowCount(frame1: frame1, data1: data1, frame2: frame2, data2: data2, fromBottom: false),
            unchangedRowCount(frame1: frame1, data1: data1, frame2: frame2, data2: data2, fromBottom: true)
        )
    }

    private static func unchangedRowCount(
        frame1: CGImage, data1: CFData,
        frame2: CGImage, data2: CFData,
        fromBottom: Bool
    ) -> Int {
        let width = min(frame1.width, frame2.width)
        let height = min(frame1.height, frame2.height)
        let maxScanRows = Int(Double(height) * maxScanPercent)
        guard width > sampleColumns, maxScanRows > 0 else { return 0 }

        let ptr1 = CFDataGetBytePtr(data1)!
        let ptr2 = CFDataGetBytePtr(data2)!
        let bpr1 = frame1.bytesPerRow
        let bpr2 = frame2.bytesPerRow
        let bpp = frame1.bitsPerPixel / 8

        let colStep = max(1, width / sampleColumns)
        var headerHeight = 0

        for scanned in 0..<maxScanRows {
            let row = fromBottom ? height - 1 - scanned : scanned
            var rowMatches = true
            var col = 0
            while col < width {
                let offset1 = row * bpr1 + col * bpp
                let offset2 = row * bpr2 + col * bpp

                let dr = abs(Int(ptr1[offset1]) - Int(ptr2[offset2]))
                let dg = abs(Int(ptr1[offset1 + 1]) - Int(ptr2[offset2 + 1]))
                let db = abs(Int(ptr1[offset1 + 2]) - Int(ptr2[offset2 + 2]))

                if dr > tolerance || dg > tolerance || db > tolerance {
                    rowMatches = false
                    break
                }
                col += colStep
            }

            if rowMatches {
                headerHeight = scanned + 1
            } else {
                break
            }
        }

        return headerHeight
    }
}
