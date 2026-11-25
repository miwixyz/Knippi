import CoreGraphics
import Darwin
import Foundation
import ImageIO
import OCRKit
import UniformTypeIdentifiers

/// Retries Vision OCR in a clean Knippi process when the OS's in-process
/// TextRecognition service has entered its broken Neural Engine state.
///
/// Some macOS preview builds return `TextRecognition.CRImageReaderError` for
/// every recognition after the first one in a process. A new process uses the
/// model's initial-load path and succeeds, so this is deliberately a fallback
/// rather than Knippi's normal OCR path.
enum OCRProcessFallback {
    private static let helperArgument = "--knippi-ocr-helper"
    private static let sensitiveHelperArgument = "--knippi-ocr-sensitive-helper"
    private static let router = OCRFallbackRouter()

    static var shouldSkipPrewarm: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27
    }

    static func recognize(
        image: CGImage,
        languages: [String]? = nil,
        level: RecognitionLevel = .accurate,
        detectURLs: Bool = true
    ) async throws -> [TextRegion] {
        try await recognize(
            image: image,
            languages: languages,
            level: level,
            detectURLs: detectURLs,
            run: TextRecognizer.recognize,
            retry: recognizeInFreshProcess,
            router: router
        )
    }

    /// Injectable runners use an isolated router unless one is explicitly shared.
    static func recognize(
        image: CGImage,
        languages: [String]?,
        level: RecognitionLevel,
        detectURLs: Bool,
        run: @Sendable (CGImage, [String]?, RecognitionLevel, Bool) async throws -> [TextRegion],
        retry: @escaping @Sendable (CGImage, [String]?, RecognitionLevel, Bool) throws -> [TextRegion] = recognizeInFreshProcess,
        router: OCRFallbackRouter = OCRFallbackRouter()
    ) async throws -> [TextRegion] {
        try await router.recognize(
            automaticLanguages: languages == nil,
            primary: { try await run(image, languages, level, detectURLs) },
            fallback: {
                try await Task.detached(priority: .userInitiated) {
                    try retry(image, languages, level, detectURLs)
                }.value
            }
        )
    }

    /// Sensitive-data boxes with the same fresh-process fallback as `recognize`.
    static func sensitiveRegions(image: CGImage, includeFaces: Bool = false) async throws -> [SensitiveRegion] {
        try await sensitiveRegions(
            image: image,
            run: { try await FaceDetector.sensitiveRegions(image: $0, includeFaces: includeFaces) },
            retry: { try sensitiveRegionsInFreshProcess(image: $0, includeFaces: includeFaces) },
            router: router
        )
    }

    static func sensitiveRegions(
        image: CGImage,
        run: @Sendable (CGImage) async throws -> [SensitiveRegion],
        retry: @escaping @Sendable (CGImage) throws -> [SensitiveRegion] = {
            try sensitiveRegionsInFreshProcess(image: $0, includeFaces: false)
        },
        router: OCRFallbackRouter = OCRFallbackRouter()
    ) async throws -> [SensitiveRegion] {
        try await router.route(
            automaticLanguages: true,
            primary: { try await run(image) },
            fallback: {
                try await Task.detached(priority: .userInitiated) { try retry(image) }.value
            }
        )
    }

    /// Runs before normal Knippi startup when this executable was launched by
    /// `recognizeInFreshProcess`. It intentionally performs only one direct
    /// Vision request, then exits without creating windows or registering
    /// shortcuts.
    static func runHelperIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if arguments.count == 5, arguments[1] == sensitiveHelperArgument,
           let inputURL = fileURL(arguments[2]),
           let outputURL = fileURL(arguments[3]) {
            let includeFaces = arguments[4] == "1"
            runHelper {
                let regions = try await FaceDetector.sensitiveRegions(
                    image: loadImage(at: inputURL), includeFaces: includeFaces)
                let data = try JSONEncoder().encode(regions.map(EncodedSensitiveRegion.init))
                try data.write(to: outputURL, options: .atomic)
            }
        }
        guard arguments.count == 6, arguments[1] == helperArgument,
              let inputURL = fileURL(arguments[2]),
              let outputURL = fileURL(arguments[3]),
              let level = recognitionLevel(for: arguments[4]) else {
            return false
        }

        let detectURLs = arguments[5] == "1"
        runHelper {
            let regions = try await TextRecognizer.recognize(
                image: loadImage(at: inputURL),
                languages: nil,
                level: level,
                detectURLs: detectURLs
            )
            let data = try JSONEncoder().encode(regions.map(EncodedRegion.init))
            try data.write(to: outputURL, options: .atomic)
        }
    }

    /// Helper arguments must be file URLs; anything else is not a helper launch.
    static func fileURL(_ argument: String) -> URL? {
        guard let url = URL(string: argument), url.isFileURL else { return nil }
        return url
    }

    /// Performs one helper job, then exits the process (0 on success).
    private static func runHelper(_ job: @escaping @Sendable () async throws -> Void) -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        let exitCode = ExitCodeBox()

        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            do {
                try await job()
                exitCode.value = 0
            } catch {
                fputs("Knippi OCR helper failed: \(error.localizedDescription)\n", stderr)
            }
        }
        semaphore.wait()
        exit(exitCode.value)
    }

    private static func recognizeInFreshProcess(
        image: CGImage,
        languages: [String]?,
        level: RecognitionLevel,
        detectURLs: Bool
    ) throws -> [TextRegion] {
        // The helper intentionally mirrors automatic language detection. The
        // current app callers do not supply an explicit language list; fail
        // closed rather than silently producing a different recognition mode.
        guard languages == nil else { throw OCRProcessFallbackError.explicitLanguagesUnsupported }
        let data = try runFreshProcess(image: image) { input, output in
            [helperArgument, input, output, level == .fast ? "fast" : "accurate", detectURLs ? "1" : "0"]
        }
        return try JSONDecoder().decode([EncodedRegion].self, from: data).map(TextRegion.init)
    }

    private static func sensitiveRegionsInFreshProcess(image: CGImage, includeFaces: Bool) throws -> [SensitiveRegion] {
        let data = try runFreshProcess(image: image) { input, output in
            [sensitiveHelperArgument, input, output, includeFaces ? "1" : "0"]
        }
        return try JSONDecoder().decode([EncodedSensitiveRegion].self, from: data).map(\.region)
    }

    /// Writes `image` to a temp PNG, runs this executable with the helper
    /// arguments built from the input/output URLs, and returns the output file.
    private static func runFreshProcess(
        image: CGImage,
        arguments: (_ input: String, _ output: String) -> [String]
    ) throws -> Data {
        guard let executableURL = Bundle.main.executableURL else {
            throw OCRProcessFallbackError.executableNotFound
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnippiOCR-\(UUID().uuidString)", isDirectory: true)
        let inputURL = directory.appendingPathComponent("input.png")
        let outputURL = directory.appendingPathComponent("regions.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writePNG(image, to: inputURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments(inputURL.absoluteString, outputURL.absoluteString)
        try runAndWait(process, timeout: helperTimeout)

        guard process.terminationStatus == 0 else {
            throw OCRProcessFallbackError.helperFailed(process.terminationStatus)
        }
        return try Data(contentsOf: outputURL)
    }

    static let helperTimeout: TimeInterval = 30

    /// Runs `process` and waits for it; terminates it and throws after `timeout`
    /// so a hung helper can't block OCR forever.
    static func runAndWait(_ process: Process, timeout: TimeInterval) throws {
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
            throw OCRProcessFallbackError.helperTimedOut(timeout)
        }
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRProcessFallbackError.invalidInputImage
        }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw OCRProcessFallbackError.cannotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OCRProcessFallbackError.cannotEncodeImage
        }
    }

    private static func recognitionLevel(for value: String) -> RecognitionLevel? {
        switch value {
        case "fast": .fast
        case "accurate": .accurate
        default: nil
        }
    }
}

private struct EncodedRegion: Codable {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let confidence: Float
    let isURL: Bool

    init(_ region: TextRegion) {
        text = region.text
        x = region.boundingBox.origin.x
        y = region.boundingBox.origin.y
        width = region.boundingBox.width
        height = region.boundingBox.height
        confidence = region.confidence
        isURL = region.isURL
    }

    func makeTextRegion() -> TextRegion {
        TextRegion(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height),
            confidence: confidence,
            isURL: isURL
        )
    }
}

/// Deliberately without the matched text: the redaction needs only kind and box,
/// and the plaintext must not land in a temp file.
private struct EncodedSensitiveRegion: Codable {
    let kind: SensitiveMatch.Kind
    let isVerified: Bool
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ region: SensitiveRegion) {
        kind = region.kind
        isVerified = region.isVerified
        x = region.boundingBox.origin.x
        y = region.boundingBox.origin.y
        width = region.boundingBox.width
        height = region.boundingBox.height
    }

    var region: SensitiveRegion {
        SensitiveRegion(kind: kind, text: "", boundingBox: CGRect(x: x, y: y, width: width, height: height),
                        isVerified: isVerified)
    }
}

private extension TextRegion {
    init(_ encoded: EncodedRegion) {
        self = encoded.makeTextRegion()
    }
}

private enum OCRProcessFallbackError: LocalizedError {
    case executableNotFound
    case explicitLanguagesUnsupported
    case invalidInputImage
    case cannotEncodeImage
    case helperFailed(Int32)
    case helperTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "Could not find Knippi's executable."
        case .explicitLanguagesUnsupported: "OCR fallback does not support explicit languages."
        case .invalidInputImage: "Could not read the temporary OCR image."
        case .cannotEncodeImage: "Could not prepare the image for OCR retry."
        case .helperFailed(let status): "OCR retry process exited with status \(status)."
        case .helperTimedOut(let seconds): "OCR retry process did not finish within \(Int(seconds)) seconds."
        }
    }
}

private final class ExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int32 = 1

    var value: Int32 {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedValue = newValue
        }
    }
}

/// Remembers a confirmed process-local Vision failure for this app lifetime.
/// Explicit language requests still try Vision because the helper cannot honor them.
actor OCRFallbackRouter {
    private var prefersFreshProcess = false

    func recognize(
        automaticLanguages: Bool,
        primary: @Sendable () async throws -> [TextRegion],
        fallback: @Sendable () async throws -> [TextRegion]
    ) async throws -> [TextRegion] {
        try await route(automaticLanguages: automaticLanguages, primary: primary, fallback: fallback)
    }

    /// Same routing for any OCR result type (e.g. sensitive-data regions).
    func route<Result: Sendable>(
        automaticLanguages: Bool,
        primary: @Sendable () async throws -> Result,
        fallback: @Sendable () async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        if prefersFreshProcess && automaticLanguages {
            let regions = try await fallback()
            try Task.checkCancellation()
            return regions
        }
        do {
            return try await primary()
        } catch {
            try Task.checkCancellation()
            guard error.localizedDescription.contains("TextRecognition.CRImageReaderError")
                    || String(describing: error).contains("CRImageReaderError") else {
                throw error
            }
            let regions = try await fallback()
            try Task.checkCancellation()
            if automaticLanguages {
                prefersFreshProcess = true
            }
            return regions
        }
    }
}
