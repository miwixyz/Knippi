import CoreGraphics

/// One area to black out, built from one or more overlapping sensitive regions.
public struct RedactionSuggestion: Sendable, Equatable {
    /// Image pixels, top-left origin.
    public let rect: CGRect
    /// False only when every contributing region is unverified.
    public let isVerified: Bool

    public init(rect: CGRect, isVerified: Bool) {
        self.rect = rect
        self.isVerified = isVerified
    }
}

/// Pads each box (Vision boxes may sit a few pixels inside the glyphs), clamps
/// to the image and merges overlapping or touching boxes until stable, so one
/// string matched as two kinds (IBAN + phone) becomes one bar.
public func redactionSuggestions(from regions: [SensitiveRegion], imageSize: CGSize) -> [RedactionSuggestion] {
    let bounds = CGRect(origin: .zero, size: imageSize)
    var items: [RedactionSuggestion] = regions.compactMap { region in
        let rect = region.boundingBox.insetBy(dx: -4, dy: -3).intersection(bounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        return RedactionSuggestion(rect: rect, isVerified: region.isVerified)
    }

    var merged = true
    while merged {
        merged = false
        outer: for i in items.indices {
            for j in items.indices where j > i && touches(items[i].rect, items[j].rect) {
                let union = RedactionSuggestion(
                    rect: items[i].rect.union(items[j].rect),
                    isVerified: items[i].isVerified || items[j].isVerified
                )
                items.remove(at: j)
                items[i] = union
                merged = true
                break outer
            }
        }
    }
    return items
}

public func redactionRects(from regions: [SensitiveRegion], imageSize: CGSize) -> [CGRect] {
    redactionSuggestions(from: regions, imageSize: imageSize).map(\.rect)
}

private func touches(_ a: CGRect, _ b: CGRect) -> Bool {
    a.minX <= b.maxX && b.minX <= a.maxX && a.minY <= b.maxY && b.minY <= a.maxY
}
