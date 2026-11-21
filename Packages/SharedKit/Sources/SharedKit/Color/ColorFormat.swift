import Foundation

/// An 8-bit sRGB colour, as sampled from the screen.
public struct RGBColor: Codable, Hashable, Sendable {
    public let r: Int, g: Int, b: Int
    public init(r: Int, g: Int, b: Int) { self.r = r; self.g = g; self.b = b }
}

/// Text formats a picked colour can be copied as.
public enum ColorFormat: String, CaseIterable, Codable, Sendable {
    case hex, rgb, hsl, swiftUI

    public var displayName: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftUI: return "SwiftUI"
        }
    }

    public func string(for c: RGBColor) -> String {
        switch self {
        case .hex: return String(format: "#%02X%02X%02X", c.r, c.g, c.b)
        case .rgb: return "rgb(\(c.r), \(c.g), \(c.b))"
        case .hsl:
            let (h, s, l) = Self.hsl(c)
            return "hsl(\(Int(h.rounded()) % 360), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftUI:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
                          Double(c.r) / 255, Double(c.g) / 255, Double(c.b) / 255)
        }
    }

    static func hsl(_ c: RGBColor) -> (Double, Double, Double) {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }
}

/// Most-recently-picked colours, newest first, without duplicates.
public struct RecentColors: Codable, Sendable {
    public private(set) var items: [RGBColor] = []
    public let limit: Int
    public init(limit: Int = 10) { self.limit = limit }
    public mutating func add(_ c: RGBColor) {
        items.removeAll { $0 == c }
        items.insert(c, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }
}
