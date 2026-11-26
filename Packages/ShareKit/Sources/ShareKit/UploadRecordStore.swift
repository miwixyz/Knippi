// Packages/ShareKit/Sources/ShareKit/UploadRecordStore.swift

import Foundation
import Observation

/// One successful Cloud Share upload, remembered locally so the user can delete the
/// public object again. Holds no credentials and no signed URLs: only the key passed to
/// `ShareDestination.upload(file:key:contentType:)`, a display name, the time, and the
/// credential-free identity of the destination (`ShareDestination.destinationID`).
public struct UploadRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let key: String
    public let uploadedAt: Date
    public let displayName: String
    public let destinationID: String

    public init(id: UUID = UUID(), key: String, uploadedAt: Date, displayName: String, destinationID: String) {
        self.id = id
        self.key = key
        self.uploadedAt = uploadedAt
        self.displayName = displayName
        self.destinationID = destinationID
    }
}

public enum UploadDeletionError: Error, Equatable, Sendable {
    /// The record was uploaded to a different destination than the one configured now.
    /// Deleting would hit the wrong bucket, so nothing is sent.
    case destinationMismatch
    case failed(ShareError)
}

public struct UploadDeletionSummary: Sendable, Equatable {
    public var deleted: Int = 0
    public var failed: [UUID: ShareError] = [:]
    /// Records that belong to another destination and were left untouched.
    public var skippedOtherDestination: Int = 0
}

/// Local list of uploads (newest first) in a JSON file with permissions 0600.
@MainActor
@Observable
public final class UploadRecordStore {
    /// Entries are tiny; the limit only guards against a runaway file. A dropped entry would
    /// stay online with no way to delete it from the app, so it is set far above real use.
    public static let defaultLimit = 5000

    public static let shared = UploadRecordStore(fileURL: defaultFileURL)

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knippi", isDirectory: true)
            .appendingPathComponent("CloudShareUploads.json")
    }

    /// Newest first.
    public private(set) var records: [UploadRecord] = []
    /// Set when the list could not be read or written; the UI shows it instead of failing silently.
    public private(set) var lastPersistenceError: String?

    public let fileURL: URL
    private let limit: Int

    public init(fileURL: URL, limit: Int = UploadRecordStore.defaultLimit) {
        self.fileURL = fileURL
        self.limit = max(1, limit)
        load()
    }

    public func record(id: UUID) -> UploadRecord? {
        records.first { $0.id == id }
    }

    /// Remembers an upload. Keeps it in memory even when writing fails (reported via
    /// `lastPersistenceError`), so it can still be deleted in this session.
    @discardableResult
    public func add(key: String, displayName: String, destinationID: String, uploadedAt: Date = Date()) -> UploadRecord {
        let record = UploadRecord(key: key, uploadedAt: uploadedAt, displayName: displayName, destinationID: destinationID)
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
        persist()
        return record
    }

    /// Removes the entry locally only — the object stays online.
    public func remove(id: UUID) {
        let before = records.count
        records.removeAll { $0.id == id }
        if records.count != before { persist() }
    }

    /// Deletes the object at the provider, then removes the entry. On any failure the
    /// entry stays and the cause is thrown.
    public func deleteUpload(_ record: UploadRecord, using destination: any ShareDestination) async throws {
        guard record.destinationID == destination.destinationID else {
            throw UploadDeletionError.destinationMismatch
        }
        // The key comes from a file on disk: never send an empty key (would address the
        // bucket itself) or one with path tricks to the provider.
        guard Self.isPlausibleKey(record.key) else {
            throw UploadDeletionError.failed(.unknown("Invalid object key in the upload list."))
        }
        do {
            try await destination.delete(key: record.key)
        } catch {
            throw UploadDeletionError.failed((error as? ShareError) ?? .unknown(error.localizedDescription))
        }
        remove(id: record.id)
    }

    /// Deletes every entry that belongs to `destination`; others are counted, not touched.
    public func deleteAllUploads(using destination: any ShareDestination) async -> UploadDeletionSummary {
        var summary = UploadDeletionSummary()
        for record in records {
            do {
                try await deleteUpload(record, using: destination)
                summary.deleted += 1
            } catch UploadDeletionError.destinationMismatch {
                summary.skippedOtherDestination += 1
            } catch UploadDeletionError.failed(let error) {
                summary.failed[record.id] = error
            } catch {
                summary.failed[record.id] = .unknown(error.localizedDescription)
            }
        }
        return summary
    }

    /// Keys are a short id plus extension, never empty, never with a slash, `..`, or control characters.
    nonisolated static func isPlausibleKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 200 && !key.contains("/") && !key.contains("..")
            && !key.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try Self.decoder.decode([UploadRecord].self, from: data)
            lastPersistenceError = nil
        } catch {
            // Never let the next save overwrite an unreadable list with an empty one:
            // those uploads are still online. Move the file aside and say so.
            records = []
            var message = error.localizedDescription
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.deletingPathExtension().lastPathComponent).unreadable-\(stamp).json")
            if (try? FileManager.default.moveItem(at: fileURL, to: aside)) != nil {
                message += " (\(aside.lastPathComponent))"
            }
            lastPersistenceError = message
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(records)
            // Write a 0600 temp file and rename it over the target: the list is never
            // readable by others, not even briefly, and never half-written.
            let tmp = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
            guard FileManager.default.createFile(
                atPath: tmp.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard Foundation.rename(tmp.path, fileURL.path) == 0 else {
                let code = errno
                try? FileManager.default.removeItem(at: tmp)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
