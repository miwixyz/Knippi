import CoreGraphics

/// One area to pixelate, built from one or more overlapping sensitive regions.
public struct RedactionSuggestion: Sendable, Equatable {
    /// Image pixels, top-left origin.
    public let rect: CGRect
    /// False only when every contributing region is unverified.
    public let isVerified: Bool
    /// Gesichtsrahmen: wird nie mit Text verschmolzen und bekommt eine eigene Blockregel.
    public let isFace: Bool

    public init(rect: CGRect, isVerified: Bool, isFace: Bool = false) {
        self.rect = rect
        self.isVerified = isVerified
        self.isFace = isFace
    }
}

/// Vision-Gesichtsrahmen sitzen eng (Augenbrauen bis Kinn, gemessen 25.11.). Haare, Stirn,
/// Ohren und Hals bleiben sonst sichtbar, deshalb wird anteilig an der Rahmengröße vergrößert.
public enum FaceBoxMargin {
    public static let sides: CGFloat = 0.4
    public static let top: CGFloat = 0.7
    public static let bottom: CGFloat = 0.35

    public static func enlarged(_ box: CGRect) -> CGRect {
        CGRect(
            x: box.minX - box.width * sides,
            y: box.minY - box.height * top,
            width: box.width * (1 + 2 * sides),
            height: box.height * (1 + top + bottom)
        )
    }
}

/// Pads each box (Vision boxes may sit a few pixels inside the glyphs), clamps
/// to the image and merges overlapping or touching boxes until stable, so one
/// string matched as two kinds (IBAN + phone) becomes one bar.
public func redactionSuggestions(from regions: [SensitiveRegion], imageSize: CGSize) -> [RedactionSuggestion] {
    let bounds = CGRect(origin: .zero, size: imageSize)
    let faces: [RedactionSuggestion] = regions.filter { $0.kind == .face }.compactMap { region in
        let rect = FaceBoxMargin.enlarged(region.boundingBox).intersection(bounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        return RedactionSuggestion(rect: rect, isVerified: region.isVerified, isFace: true)
    }
    var items: [RedactionSuggestion] = regions.filter { $0.kind != .face }.compactMap { region in
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
    // Gesichter bleiben einzeln (jedes abwählbar) und verschmelzen nie mit Textrahmen.
    return items + faces
}

public func redactionRects(from regions: [SensitiveRegion], imageSize: CGSize) -> [CGRect] {
    redactionSuggestions(from: regions, imageSize: imageSize).map(\.rect)
}

private func touches(_ a: CGRect, _ b: CGRect) -> Bool {
    a.minX <= b.maxX && b.minX <= a.maxX && a.minY <= b.maxY && b.minY <= a.maxY
}
