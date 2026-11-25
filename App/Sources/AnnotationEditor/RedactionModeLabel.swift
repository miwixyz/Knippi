import AnnotationKit

extension RedactionMode {
    /// Lokalisierte Anzeige (Text(String) wäre nicht übersetzt).
    var localizedLabel: String {
        switch self {
        case .pixelate: String(localized: "Pixelate")
        case .blur: String(localized: "Blur")
        case .solid: String(localized: "Black Bar")
        case .erase: String(localized: "Erase")
        }
    }
}
