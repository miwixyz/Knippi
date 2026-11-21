import AppKit
import SharedKit
import SwiftUI

/// Background style for the Beautify background surrounding the screenshot.
enum BeautifyBackgroundStyle: Codable, Hashable {
    /// Flat color fill (the original behaviour).
    case solid
    /// A heavily blurred, saturation-boosted copy of the screenshot
    /// used as the backdrop — extends the image's own colours into the
    /// padding area for a "liquid glass" look.
    case liquidGlass
    /// Transparent, for rounded corners and shadow alone.
    case none
    /// One of the built-in gradients.
    case gradient(BeautifyGradient)
    /// A picture chosen by the user, drawn aspect-fill.
    case image(URL)

    private enum CodingKeys: String, CodingKey { case gradient, image }

    /// The simple cases stay a plain string, which is also what every version
    /// before gradients wrote. Anything unreadable becomes `.solid`.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            switch raw {
            case "liquidGlass": self = .liquidGlass
            case "none": self = .none
            default: self = .solid
            }
            return
        }
        let keyed = try? decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? keyed?.decode(String.self, forKey: .gradient) {
            self = .gradient(BeautifyGradient(rawValue: raw) ?? .polarlicht)
        } else if let raw = try? keyed?.decode(String.self, forKey: .image), let url = URL(string: raw), url.isFileURL {
            self = .image(url)
        } else {
            self = .solid
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .solid:
            var single = encoder.singleValueContainer()
            try single.encode("solid")
        case .liquidGlass:
            var single = encoder.singleValueContainer()
            try single.encode("liquidGlass")
        case .none:
            var single = encoder.singleValueContainer()
            try single.encode("none")
        case .gradient(let gradient):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(gradient.rawValue, forKey: .gradient)
        case .image(let url):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(url.absoluteString, forKey: .image)
        }
    }
}

enum BeautifyGradient: String, Codable, CaseIterable, Identifiable {
    case polarlicht, abendglut, graphit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .polarlicht: String(localized: "Aurora")
        case .abendglut: String(localized: "Sunset Glow")
        case .graphit: String(localized: "Graphite")
        }
    }
}

/// Output format of the Beautify canvas. The canvas grows in the too-short
/// direction until the ratio matches; the screenshot stays centred.
enum BeautifyAspect: String, Codable, CaseIterable, Identifiable {
    case free, wide16x9, square1x1, portrait4x5

    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .wide16x9: 16.0 / 9
        case .square1x1: 1
        case .portrait4x5: 4.0 / 5
        }
    }

    var label: String {
        switch self {
        case .free: String(localized: "Free")
        case .wide16x9: "16:9"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        }
    }
}

struct BeautifySettings {
    var isEnabled = false
    var backgroundStyle: BeautifyBackgroundStyle = .solid
    var backgroundColor: Color = .white
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var shadowEnabled = true
    var shadowRadius: CGFloat = 20
    var aspect: BeautifyAspect = .free

    var clampedPadding: CGFloat { max(0, padding) }
    var clampedCornerRadius: CGFloat { max(0, cornerRadius) }
    var clampedShadowRadius: CGFloat { shadowEnabled ? max(0, shadowRadius) : 0 }
    var shadowInset: CGFloat { shadowEnabled ? clampedShadowRadius + 6 : 0 }
    var outerInset: CGFloat { clampedPadding + shadowInset }
    /// Corner radius of the whole picture (background included), concentric with the
    /// screenshot's own corners: inner radius plus the margin (Michael, 21.11.: "das
    /// ganze Fenster mit Hintergrund soll abgerundete Ecken haben").
    var outerCornerRadius: CGFloat { clampedCornerRadius + clampedPadding }

    /// Whole-pixel canvas size for an image of `imageSize`: uniform
    /// `outerInset` on every side, then widened or heightened to `aspect`.
    func canvasSize(for imageSize: CGSize) -> CGSize {
        var width = (imageSize.width + outerInset * 2).rounded()
        var height = (imageSize.height + outerInset * 2).rounded()
        if let ratio = aspect.ratio, width > 0, height > 0 {
            if width / height < ratio {
                width = (height * ratio).rounded()
            } else {
                height = (width / ratio).rounded()
            }
        }
        return CGSize(width: width, height: height)
    }

    /// Space left and right / above and below the image inside the canvas.
    func canvasInsets(for imageSize: CGSize) -> (horizontal: CGFloat, vertical: CGFloat) {
        let canvas = canvasSize(for: imageSize)
        return ((canvas.width - imageSize.width) / 2, (canvas.height - imageSize.height) / 2)
    }
}

extension BeautifySettings {
    private struct Style: Codable {
        var backgroundStyle: BeautifyBackgroundStyle
        var backgroundColor: [CGFloat]
        var padding: CGFloat
        var cornerRadius: CGFloat
        var shadowEnabled: Bool
        var shadowRadius: CGFloat
        var aspect: BeautifyAspect

        init(_ settings: BeautifySettings) {
            let color = NSColor(settings.backgroundColor).usingColorSpace(.sRGB) ?? .white
            backgroundStyle = settings.backgroundStyle
            backgroundColor = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            padding = settings.padding
            cornerRadius = settings.cornerRadius
            shadowEnabled = settings.shadowEnabled
            shadowRadius = settings.shadowRadius
            aspect = settings.aspect
        }

        /// Every field is optional so styles saved by older versions (no
        /// `aspect`) and unknown values load with defaults instead of failing.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = Style(BeautifySettings())
            backgroundStyle = (try? c.decodeIfPresent(BeautifyBackgroundStyle.self, forKey: .backgroundStyle)) ?? fallback.backgroundStyle
            backgroundColor = (try? c.decodeIfPresent([CGFloat].self, forKey: .backgroundColor)) ?? fallback.backgroundColor
            padding = (try? c.decodeIfPresent(CGFloat.self, forKey: .padding)) ?? fallback.padding
            cornerRadius = (try? c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)) ?? fallback.cornerRadius
            shadowEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .shadowEnabled)) ?? fallback.shadowEnabled
            shadowRadius = (try? c.decodeIfPresent(CGFloat.self, forKey: .shadowRadius)) ?? fallback.shadowRadius
            let rawAspect = (try? c.decodeIfPresent(String.self, forKey: .aspect)) ?? nil
            aspect = rawAspect.flatMap(BeautifyAspect.init(rawValue:)) ?? fallback.aspect
        }
    }

    /// The last style set in the editor, with Beautify itself left off.
    static func saved(settings: AppSettings = AppSettings()) -> BeautifySettings {
        var result = BeautifySettings()
        guard let data = settings.beautifyStyle,
              let style = try? JSONDecoder().decode(Style.self, from: data) else { return result }
        result.backgroundStyle = style.backgroundStyle
        if style.backgroundColor.count == 4 {
            let c = style.backgroundColor
            result.backgroundColor = Color(nsColor: NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3]))
        }
        result.padding = style.padding
        result.cornerRadius = style.cornerRadius
        result.shadowEnabled = style.shadowEnabled
        result.shadowRadius = style.shadowRadius
        result.aspect = style.aspect
        return result
    }

    func saveStyle(settings: AppSettings = AppSettings()) {
        settings.beautifyStyle = try? JSONEncoder().encode(Style(self))
    }
}
