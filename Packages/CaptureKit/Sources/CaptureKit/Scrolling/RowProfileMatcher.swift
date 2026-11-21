// Packages/CaptureKit/Sources/CaptureKit/Scrolling/RowProfileMatcher.swift
import CoreGraphics

/// Finds how far a page was scrolled between two frames by comparing row
/// profiles (brightness of a few column blocks per row).
///
/// Replaces Vision's translational registration, which measured nonsense for
/// shifts beyond roughly a tenth of the frame (measured 2026-11-21 on real
/// Safari frames: true 100–900 px, Vision −31…+26).
///
/// Text repeats: in a list, a table or a log, lines further down can look
/// almost the same and differ only in a narrow detail such as a number. A
/// coarse search over the row profiles therefore only proposes candidates;
/// each is checked tile by tile on a sharper copy, and only a shift that
/// matches everywhere — and is the only one that does — is accepted.
enum RowProfileMatcher {
    /// Brightness of `columns` blocks for every row, top row first, plus a
    /// sharper copy (`detail`) for checking candidates.
    struct Profile {
        let rows: Int
        let columns: Int
        let values: [UInt8]
        let detail: Gray?

        init?(_ image: CGImage, columns: Int = 256, detailColumns: Int = 1024) {
            guard let coarse = Gray(image, columns: columns) else { return nil }
            self.rows = coarse.rows
            self.columns = coarse.columns
            self.values = coarse.values
            self.detail = Gray(image, columns: min(image.width, detailColumns))
        }

        init(rows: Int, columns: Int, values: [UInt8], detail: Gray? = nil) {
            self.rows = rows
            self.columns = columns
            self.values = values
            self.detail = detail
        }
    }

    /// A grayscale copy of a frame, scaled to `columns` wide, top row first.
    struct Gray {
        let rows: Int
        let columns: Int
        let values: [UInt8]

        init?(_ image: CGImage, columns: Int) {
            let rows = image.height
            guard rows > 0, columns > 0, image.width > 0,
                  let ctx = CGContext(
                      data: nil, width: columns, height: rows, bitsPerComponent: 8,
                      bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            guard let data = ctx.data else { return nil }
            self.rows = rows
            self.columns = columns
            self.values = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: rows * columns))
        }
    }

    struct Match: Equatable {
        /// Rows the content moved up (scrolled down); negative when scrolled up.
        let offset: Int
        /// Mean brightness difference of the row profiles at `offset`, 0…255.
        let error: Double
        /// Lowest profile difference among the candidates that failed.
        let runnerUpError: Double
    }

    /// Largest mean profile difference still worth checking. Measured on real
    /// frames: true matches 0.3–2.9 (Safari, Mail, Preview).
    static let maxError = 4.0
    static let strictMaxError = 3.0

    /// The detail check: tiles of `tileColumns` × `tileRows`; a tile whose
    /// mean difference exceeds `tileLimit` is a mismatch. Measured 2026-11-21
    /// on real frame pairs (Safari, Mail, Preview):
    /// - true shift, page at rest: 0 mismatching tiles;
    /// - true shift while Safari still glides, or before its header sticks:
    ///   up to 3 % and 6 % of the tiles (text re-rendered, header band);
    /// - look-alike six or twelve lines away: 20–50 % in Safari, but in a PDF
    ///   with wide empty margins as few as 20 tiles (under 1 %).
    static let tileColumns = 8
    static let tileRows = 16
    static let tileLimit = 24.0
    /// Mismatching tiles tolerated at the true shift: a blinking caret.
    static let allowedBadTiles = 2
    /// While tracking: largest share of mismatching tiles still accepted when
    /// every other candidate is clearly worse (`relativeMargin`).
    static let maxBadShare = 0.08
    static let relativeMargin = (factor: 3.0, plus: 0.02)

    /// Offset of `later` relative to `earlier`, ignoring `top` rows (sticky
    /// header) and `bottom` rows (sticky footer). Nil when no offset is clearly
    /// right: an empty area, too little overlap, a frame caught mid-redraw, or
    /// several look-alike shifts that pass alike. `strict` is for re-finding the
    /// page after the track was lost, when look-alikes are the main danger:
    /// then only a shift matching cleanly everywhere counts.
    static func offset(
        from earlier: Profile, to later: Profile, top: Int, bottom: Int, strict: Bool = false
    ) -> Match? {
        let limit = strict ? strictMaxError : maxError
        let candidates = candidates(from: earlier, to: later, top: top, bottom: bottom)
        guard let a = earlier.detail, let b = later.detail, a.rows == b.rows, a.columns == b.columns else {
            // No detail copy (hand-made profiles): margin rule only.
            guard let best = candidates.first, best.error <= limit else { return nil }
            let runnerUp = candidates.first { abs($0.shift - best.shift) > 8 }?.error ?? .infinity
            guard runnerUp >= best.error * 1.5 + 0.2 else { return nil }
            return Match(offset: best.shift, error: best.error, runnerUpError: runnerUp)
        }
        let checked = candidates
            .filter { $0.error <= limit }
            .compactMap { candidate -> (shift: Int, error: Double, bad: Int, share: Double)? in
                guard let tiles = mismatch(a, b, shift: candidate.shift, top: top, bottom: bottom) else { return nil }
                return (candidate.shift, candidate.error, tiles.bad, Double(tiles.bad) / Double(tiles.total))
            }
            .sorted { $0.share < $1.share }
        guard let best = checked.first else { return nil }
        let others = checked.filter { abs($0.shift - best.shift) > 8 }
        let allowed = strict ? 0 : allowedBadTiles
        let clean = best.bad <= allowed && others.allSatisfy { $0.bad > allowed }
        let clearlyBest = !strict && best.share <= maxBadShare
            && others.allSatisfy { $0.share >= best.share * relativeMargin.factor + relativeMargin.plus }
        guard clean || clearlyBest else { return nil }
        let runnerUp = candidates.first { abs($0.shift - best.shift) > 8 }?.error ?? .infinity
        return Match(offset: best.shift, error: best.error, runnerUpError: runnerUp)
    }

    /// Up to `candidateCount` well-separated shifts with the lowest profile
    /// difference, each refined to the exact row, best first.
    static let candidateCount = 12

    static func candidates(
        from a: Profile, to b: Profile, top: Int, bottom: Int
    ) -> [(shift: Int, error: Double)] {
        guard a.rows == b.rows, a.columns == b.columns else { return [] }
        // The last blocks hold the scrollbar, whose thumb moves while scrolling.
        let usable = max(1, a.columns - max(2, a.columns / 32))
        let start = max(0, top)
        let end = a.rows - max(0, bottom)
        let area = end - start
        let minOverlap = max(40, area / 5)
        guard area > minOverlap else { return [] }
        let maxShift = area - minOverlap

        return a.values.withUnsafeBufferPointer { pa in
            b.values.withUnsafeBufferPointer { pb -> [(shift: Int, error: Double)] in
                // 1. Coarse: every 4th shift, every 4th row, every 4th column.
                var coarse: [(shift: Int, error: Double)] = []
                var shift = -maxShift
                while shift <= maxShift {
                    coarse.append((shift, meanDifference(pa, pb, columns: a.columns, usable: usable, columnStep: 4,
                                                         start: start, end: end, shift: shift, rowStep: 4)))
                    shift += 4
                }
                // 2. Candidates: the lowest, well apart.
                var picked: [Int] = []
                for entry in coarse.sorted(by: { $0.error < $1.error }) where picked.count < candidateCount {
                    if picked.allSatisfy({ abs($0 - entry.shift) > 12 }) { picked.append(entry.shift) }
                }
                // 3. Fine: every column, every second row, ±4 around each, then
                //    the exact row with every row: trimming hides the few edge
                //    rows that tell neighbouring shifts apart.
                var refined: [(shift: Int, error: Double)] = []
                for candidate in picked {
                    var best = (shift: candidate, error: Double.infinity)
                    for fine in max(-maxShift, candidate - 4)...min(maxShift, candidate + 4) {
                        let error = trimmedDifference(pa, pb, columns: a.columns, usable: usable,
                                                      start: start, end: end, shift: fine)
                        if error < best.error { best = (fine, error) }
                    }
                    var exact = (shift: best.shift, error: Double.infinity)
                    for fine in max(-maxShift, best.shift - 3)...min(maxShift, best.shift + 3) {
                        let error = meanDifference(pa, pb, columns: a.columns, usable: usable, columnStep: 1,
                                                   start: start, end: end, shift: fine, rowStep: 1)
                        if error < exact.error { exact = (fine, error) }
                    }
                    refined.append((exact.shift, best.error))
                }
                return refined.sorted { $0.error < $1.error }
            }
        }
    }

    /// Tile rows at the top or bottom edge of the overlap that are skipped
    /// while they mismatch: a translucent toolbar showing blurred content
    /// (Mail), a header that only sticks after scrolling a little (Safari).
    static let maxEdgeTileRows = 8

    /// Mismatching and total tiles at `shift`, without mismatching edge rows;
    /// nil when too little overlap is left.
    static func mismatch(_ a: Gray, _ b: Gray, shift: Int, top: Int, bottom: Int) -> (bad: Int, total: Int)? {
        let start = max(0, top)
        let end = a.rows - max(0, bottom)
        let first = max(start, start - shift)
        let last = min(end, end - shift)
        let usable = a.columns - a.columns / 32
        guard last - first >= tileRows, usable >= tileColumns else { return nil }
        let threshold = Int(tileLimit * Double(tileColumns * tileRows))
        let tilesPerRow = usable / tileColumns
        let badPerRow: [Int] = a.values.withUnsafeBufferPointer { pa in
            b.values.withUnsafeBufferPointer { pb in
                var rows: [Int] = []
                var tileTop = first
                while tileTop + tileRows <= last {
                    var bad = 0
                    var tileLeft = 0
                    while tileLeft + tileColumns <= usable {
                        var sum = 0
                        for row in tileTop..<(tileTop + tileRows) {
                            let rowA = (row + shift) * a.columns
                            let rowB = row * b.columns
                            for column in tileLeft..<(tileLeft + tileColumns) {
                                let difference = Int(pa[rowA + column]) - Int(pb[rowB + column])
                                sum += difference < 0 ? -difference : difference
                            }
                        }
                        if sum > threshold { bad += 1 }
                        tileLeft += tileColumns
                    }
                    rows.append(bad)
                    tileTop += tileRows
                }
                return rows
            }
        }
        var lower = 0
        var upper = badPerRow.count
        while lower < min(maxEdgeTileRows, upper), badPerRow[lower] > 0 { lower += 1 }
        while upper - lower > 0, badPerRow.count - upper < maxEdgeTileRows, badPerRow[upper - 1] > 0 { upper -= 1 }
        let kept = upper - lower
        guard kept >= max(2, badPerRow.count / 2) else { return nil }
        return (badPerRow[lower..<upper].reduce(0, +), kept * tilesPerRow)
    }

    /// Share of best-matching rows that count in the fine comparison. The rest
    /// may differ: a header that only sticks after scrolling a little, a
    /// blinking caret, an animation.
    static let keptRowShare = 0.85

    /// Like `meanDifference`, every second row and every column, but averaged
    /// over the best `keptRowShare` of the rows only.
    private static func trimmedDifference(
        _ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>,
        columns: Int, usable: Int, start: Int, end: Int, shift: Int
    ) -> Double {
        let first = max(start, start - shift)
        let last = min(end, end - shift)
        guard last > first else { return .infinity }
        var rowErrors: [Int] = []
        rowErrors.reserveCapacity((last - first) / 2 + 1)
        var row = first
        while row < last {
            let rowB = row * columns
            let rowA = (row + shift) * columns
            var sum = 0
            for column in 0..<usable {
                let difference = Int(a[rowA + column]) - Int(b[rowB + column])
                sum += difference < 0 ? -difference : difference
            }
            rowErrors.append(sum)
            row += 2
        }
        rowErrors.sort()
        let kept = max(1, Int(Double(rowErrors.count) * keptRowShare))
        let total = rowErrors.prefix(kept).reduce(0, +)
        return Double(total) / Double(kept * usable)
    }

    /// Mean |a[i + shift] − b[i]| over overlapping rows i in start..<end.
    private static func meanDifference(
        _ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>,
        columns: Int, usable: Int, columnStep: Int, start: Int, end: Int, shift: Int, rowStep: Int
    ) -> Double {
        let first = max(start, start - shift)
        let last = min(end, end - shift)
        guard last > first else { return .infinity }
        var sum = 0
        var count = 0
        var row = first
        while row < last {
            let rowB = row * columns
            let rowA = (row + shift) * columns
            var column = 0
            while column < usable {
                let difference = Int(a[rowA + column]) - Int(b[rowB + column])
                sum += difference < 0 ? -difference : difference
                count += 1
                column += columnStep
            }
            row += rowStep
        }
        return count > 0 ? Double(sum) / Double(count) : .infinity
    }
}
