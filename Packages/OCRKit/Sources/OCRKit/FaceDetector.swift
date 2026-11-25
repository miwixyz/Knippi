import CoreGraphics
import Foundation
import Vision

/// Gesichtssuche für „Vertrauliches finden“ (Spec Knippi 0.6.0, Teil A).
///
/// Läuft komplett auf dem Gerät (Apple Vision, kein Netz). Sie ist eine **Hilfe, kein Schutz**:
/// gut sichtbare Gesichter werden meist gefunden, kleine oder verdeckte können fehlen.
///
/// Suche = neue `DetectFaceRectanglesRequest` auf dem ganzen Bild (bei sehr großen Bildern in
/// Streifen) vereinigt mit 2× vergrößerten, überlappenden 640-px-Kacheln (neue und klassische
/// Anfrage). Gemessen am 25.11.2026: jede Teilsuche findet Gesichter, die die anderen übersehen.
public enum FaceDetector {
    /// Darunter gilt ein Gesichtsrahmen als „unsicher“ und wird gestrichelt gezeigt.
    public static let verifiedConfidence: Float = 0.5
    /// Kantenlänge der Kacheln (Bildpixel, vor der Vergrößerung) und Schrittweite (30 % Überlappung).
    static let tile = 640
    static let tileStep = 448
    /// Mehr Kacheln als das: nur Ganzbild- bzw. Streifensuche (sonst Minuten bei Scroll-Aufnahmen).
    static let maxTiles = 80
    /// Ab dieser Kantenlänge wird nie ein ganzes Bild an Vision gegeben (gemessen: 30 439 px = 23 s,
    /// in Streifen 0,7 s).
    static let stripThreshold = 8000
    static let stripLength = 2000
    static let stripOverlap = 300

    struct Face: Equatable, Sendable {
        var rect: CGRect
        var confidence: Float
    }

    // MARK: Öffentlich

    /// Gesichtsrahmen in Bildpixeln (links oben), roh wie von Vision (eng um Augenbrauen bis Kinn).
    public static func regions(in image: CGImage) async throws -> [SensitiveRegion] {
        let faces = try await detectFaces(in: image)
        return faces.map {
            SensitiveRegion(kind: .face, text: "", boundingBox: $0.rect, isVerified: $0.confidence >= verifiedConfidence)
        }
    }

    /// Vertrauliche Texte plus (optional) Gesichter, beide Suchen laufen gleichzeitig.
    /// Ein Fehler in einer der beiden Suchen wird weitergereicht, nie still verschluckt.
    public static func sensitiveRegions(image: CGImage, includeFaces: Bool) async throws -> [SensitiveRegion] {
        guard includeFaces else { return try await TextRecognizer.sensitiveRegions(image: image) }
        let source = image
        async let text = TextRecognizer.sensitiveRegions(image: source)
        async let faces = regions(in: source)
        return try await text + faces
    }

    // MARK: Planung (rein, getestet)

    /// Fenster für die Ganzbild-Suche: das Bild selbst, oder bei Kantenlänge über `stripThreshold`
    /// Streifen von `stripLength` mit `stripOverlap` Überlappung (je Achse, die zu lang ist).
    static func searchWindows(width: Int, height: Int) -> [CGRect] {
        func ranges(_ length: Int) -> [(Int, Int)] {
            guard length > stripThreshold else { return [(0, length)] }
            var result: [(Int, Int)] = []
            var start = 0
            while start + stripLength < length {
                result.append((start, stripLength))
                start += stripLength - stripOverlap
            }
            result.append((max(0, length - stripLength), min(stripLength, length)))
            return result
        }
        var windows: [CGRect] = []
        for y in ranges(height) {
            for x in ranges(width) {
                windows.append(CGRect(x: x.0, y: y.0, width: x.1, height: y.1))
            }
        }
        return windows
    }

    /// Kachelanfänge entlang einer Achse; die letzte Kachel liegt bündig am Ende.
    static func tileStarts(length: Int) -> [Int] {
        if length <= tile { return [0] }
        var starts: [Int] = []
        var position = 0
        while position + tile < length {
            starts.append(position)
            position += tileStep
        }
        starts.append(length - tile)
        return starts
    }

    static func tileRects(width: Int, height: Int) -> [CGRect] {
        var rects: [CGRect] = []
        for y in tileStarts(length: height) {
            for x in tileStarts(length: width) {
                rects.append(CGRect(x: x, y: y, width: min(tile, width), height: min(tile, height)))
            }
        }
        return rects
    }

    /// Entfernt Mehrfachfunde. Strenger als bei Text: ein Rahmen zählt als Duplikat, wenn seine
    /// Mitte im um 50 % vergrößerten Rahmen eines größeren liegt (ein Doppelrahmen auf der
    /// Brust eines erkannten Gesichts, gemessen 25.11.) oder beide sich stark überdecken.
    /// Größere Rahmen gewinnen, die höhere Sicherheit bleibt erhalten.
    static func deduplicated(_ faces: [Face]) -> [Face] {
        var kept: [Face] = []
        for face in faces.sorted(by: { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }) {
            if let index = kept.firstIndex(where: { isDuplicate(face.rect, of: $0.rect) }) {
                kept[index].confidence = max(kept[index].confidence, face.confidence)
            } else {
                kept.append(face)
            }
        }
        return kept
    }

    static func isDuplicate(_ small: CGRect, of large: CGRect) -> Bool {
        let grown = large.insetBy(dx: -large.width * 0.25, dy: -large.height * 0.25)
        if grown.contains(CGPoint(x: small.midX, y: small.midY)) { return true }
        let inter = small.intersection(large)
        guard !inter.isNull else { return false }
        let area = inter.width * inter.height
        let union = small.width * small.height + large.width * large.height - area
        return union > 0 && area / union > 0.2
    }

    // MARK: Ausführung

    private enum Job: Sendable {
        case modern(window: CGRect, scale: Int)
        case classic(window: CGRect, scale: Int)
    }

    static func detectFaces(in image: CGImage) async throws -> [Face] {
        let width = image.width, height = image.height
        // D = neue API ganz + auf Kacheln, B = klassisch ganz + auf Kacheln (Messung A0e, 25.11.).
        var jobs: [Job] = searchWindows(width: width, height: height).flatMap {
            [Job.modern(window: $0, scale: 1), Job.classic(window: $0, scale: 1)]
        }
        let tiles = tileRects(width: width, height: height)
        if tiles.count <= maxTiles {
            for rect in tiles {
                jobs.append(.modern(window: rect, scale: 2))
                jobs.append(.classic(window: rect, scale: 2))
            }
        }

        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let source = image
        var all: [Face] = []
        try await withThrowingTaskGroup(of: [Face].self) { group in
            var iterator = jobs.makeIterator()
            var running = 0
            func addNext() -> Bool {
                guard let job = iterator.next() else { return false }
                group.addTask { try await run(job, on: source) }
                running += 1
                return true
            }
            while running < limit, addNext() {}
            while let faces = try await group.next() {
                all += faces
                running -= 1
                _ = addNext()
            }
        }
        return deduplicated(all)
    }

    private static func run(_ job: Job, on image: CGImage) async throws -> [Face] {
        switch job {
        case let .modern(window, scale):
            return try await detect(in: image, window: window, scale: scale) { try await modernFaces(in: $0) }
        case let .classic(window, scale):
            return try await detect(in: image, window: window, scale: scale) { try await classicFaces(in: $0) }
        }
    }

    private static func detect(
        in image: CGImage, window: CGRect, scale: Int,
        using detector: (CGImage) async throws -> [Face]
    ) async throws -> [Face] {
        let isWhole = window.width == CGFloat(image.width) && window.height == CGFloat(image.height)
        guard let cropped = isWhole ? image : image.cropping(to: window) else { return [] }
        guard let input = scale == 1 ? cropped : scaled(cropped, by: scale) else { return [] }
        let factor = CGFloat(scale)
        return try await detector(input).map {
            Face(
                rect: CGRect(x: window.minX + $0.rect.minX / factor, y: window.minY + $0.rect.minY / factor,
                             width: $0.rect.width / factor, height: $0.rect.height / factor),
                confidence: $0.confidence
            )
        }
    }

    private static func modernFaces(in image: CGImage) async throws -> [Face] {
        let observations = try await DetectFaceRectanglesRequest().perform(on: image)
        let size = CGSize(width: image.width, height: image.height)
        return observations.map {
            Face(rect: $0.boundingBox.toImageCoordinates(size, origin: .upperLeft), confidence: $0.confidence)
        }
    }

    private static func classicFaces(in image: CGImage) async throws -> [Face] {
        let source = image
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNDetectFaceRectanglesRequest()
                    try VNImageRequestHandler(cgImage: source, options: [:]).perform([request])
                    let w = CGFloat(source.width), h = CGFloat(source.height)
                    let faces = (request.results ?? []).map { observation -> Face in
                        let box = observation.boundingBox
                        return Face(
                            rect: CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h),
                            confidence: observation.confidence
                        )
                    }
                    continuation.resume(returning: faces)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func scaled(_ image: CGImage, by factor: Int) -> CGImage? {
        let width = image.width * factor, height = image.height * factor
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
