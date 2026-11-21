// Packages/ExportKit/Sources/ExportKit/ExportOptions.swift
import Foundation
import CoreMedia
import SharedKit

public enum ExportFormat: String, Sendable {
    case mp4
    case gif
}

public struct ExportOptions: Sendable {
    public let format: ExportFormat
    public let quality: ExportQuality
    public let destination: URL
    // `timeRange` removed: no caller set it and the merged-audio path ignored it;
    // trimming goes through CutExporter (audit E7, 21.11.).

    public init(format: ExportFormat, quality: ExportQuality, destination: URL) {
        self.format = format
        self.quality = quality
        self.destination = destination
    }
}

public enum ExportError: Error, Sendable, LocalizedError {
    case sourceFileNotFound
    case exportSessionFailed(String)
    case frameExtractionFailed
    case gifCreationFailed
    case cancelled

    /// Readable text for the editor's error alert, which used to show the raw
    /// enum dump (audit E24, 21.11.).
    public var errorDescription: String? {
        switch self {
        // Looked up in the app's string catalog (Bundle.main), so the dialog is German too.
        case .sourceFileNotFound: return String(localized: "The recording file could not be found.")
        case .exportSessionFailed(let reason): return String(localized: "The video could not be exported: \(reason)")
        case .frameExtractionFailed: return String(localized: "The frames of the video could not be read.")
        case .gifCreationFailed: return String(localized: "The GIF could not be created.")
        case .cancelled: return String(localized: "The export was cancelled.")
        }
    }
}

public enum ExportStage: String, Sendable {
    case preparing
    case trimming
    case compositing
    case encoding
    case finalizing

    public var userDescription: String {
        switch self {
        case .preparing:
            return "Preparing export…"
        case .trimming:
            return "Applying trims…"
        case .compositing:
            return "Rendering edited frames…"
        case .encoding:
            return "Encoding video…"
        case .finalizing:
            return "Finalizing file…"
        }
    }
}

public struct ExportStatus: Sendable {
    public let stage: ExportStage
    public let fractionCompleted: Double

    public init(stage: ExportStage, fractionCompleted: Double) {
        self.stage = stage
        self.fractionCompleted = fractionCompleted
    }
}
