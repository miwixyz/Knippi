// Packages/ShareKit/Sources/ShareKit/ShareCoordinator.swift

import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

public enum UploadState: Sendable {
    case idle
    case uploading
    case succeeded(URL)
    case failed(ShareError)
}

public struct ShareUploadResult: Sendable {
    public let url: URL
    public let record: UploadRecord
}

@MainActor
@Observable
public final class ShareCoordinator {
    public private(set) var state: UploadState = .idle
    public let destination: ShareDestination
    /// Read when each upload starts; when `true` the link is copied right away
    /// instead of after the upload finishes.
    private let copiesLinkWhenUploadStarts: @MainActor () -> Bool
    private var uploadQueue: [UploadRequest] = []
    private var isProcessingQueue = false
    private var isInvalidated = false

    /// Called when the Cloud Share configuration is replaced or reset. Windows that still hold
    /// this coordinator (open Quick Access cards) must not upload with the old credentials
    /// (audit Q11, 21.11.).
    public func invalidate() {
        isInvalidated = true
        let pending = uploadQueue
        uploadQueue.removeAll()
        pending.forEach { $0.continuation.resume(throwing: ShareError.notConfigured) }
    }

    private struct UploadRequest {
        let file: URL
        let contentType: String
        let displayName: String?
        let continuation: CheckedContinuation<ShareUploadResult, Error>
    }

    /// Every successful upload is remembered here so the link can be deleted later.
    public let uploadRecords: UploadRecordStore

    /// `uploadRecords` defaults to `UploadRecordStore.shared` (Application Support);
    /// tests pass their own store.
    public init(
        destination: ShareDestination,
        uploadRecords: UploadRecordStore? = nil,
        copiesLinkWhenUploadStarts: @escaping @MainActor () -> Bool = { false }
    ) {
        self.destination = destination
        self.uploadRecords = uploadRecords ?? .shared
        self.copiesLinkWhenUploadStarts = copiesLinkWhenUploadStarts
    }

    /// Uploads `file` and copies its URL to the clipboard — on success, or as soon
    /// as the upload starts when `copiesLinkWhenUploadStarts` says so.
    /// Returns the URL on success; throws on failure. Updates `state` for observers.
    /// On failure an early-copied link is removed again (previous clipboard text restored).
    @discardableResult
    public func upload(file: URL, contentType: String) async throws -> URL {
        try await uploadReturningRecord(file: file, contentType: contentType).url
    }

    /// Same as `upload(file:contentType:)`, but also returns the local record of the upload
    /// (needed to delete the link again). `displayName` defaults to the object key.
    public func uploadReturningRecord(file: URL, contentType: String, displayName: String? = nil) async throws -> ShareUploadResult {
        guard !isInvalidated else { throw ShareError.notConfigured }
        return try await withCheckedThrowingContinuation { continuation in
            uploadQueue.append(
                UploadRequest(
                    file: file,
                    contentType: contentType,
                    displayName: displayName,
                    continuation: continuation
                )
            )
            guard !isProcessingQueue else { return }
            isProcessingQueue = true
            Task { await processUploadQueue() }
        }
    }

    private func processUploadQueue() async {
        defer { isProcessingQueue = false }

        while !uploadQueue.isEmpty {
            let request = uploadQueue.removeFirst()
            state = .uploading
            let id = IDGenerator.shortID()
            let ext = request.file.pathExtension
            let key = ext.isEmpty ? id : "\(id).\(ext)"
            let copiedEarly = copiesLinkWhenUploadStarts()
            let earlyURL = destination.publicURL(for: key)
            let previousClipboard = copiedEarly ? currentClipboardString() : nil
            if copiedEarly {
                copyToClipboard(earlyURL)
            }

            do {
                let url = try await destination.upload(
                    file: request.file,
                    key: key,
                    contentType: request.contentType
                )
                let record = uploadRecords.add(
                    key: key,
                    displayName: request.displayName ?? key,
                    destinationID: destination.destinationID
                )
                state = .succeeded(url)
                if !copiedEarly { copyToClipboard(url) }
                request.continuation.resume(returning: ShareUploadResult(url: url, record: record))
            } catch {
                if copiedEarly { revokeEarlyCopy(earlyURL, restoring: previousClipboard) }
                let mapped = (error as? ShareError) ?? ShareError.unknown(error.localizedDescription)
                state = .failed(mapped)
                request.continuation.resume(throwing: mapped)
            }
        }
    }

    public func reset() {
        state = .idle
    }

    private func currentClipboardString() -> String? {
        #if canImport(AppKit)
        NSPasteboard.general.string(forType: .string)
        #else
        nil
        #endif
    }

    /// Nimmt den früh kopierten Link nur zurück, wenn der Nutzer inzwischen nichts anderes kopiert hat.
    private func revokeEarlyCopy(_ url: URL, restoring previous: String?) {
        #if canImport(AppKit)
        guard NSPasteboard.general.string(forType: .string) == url.absoluteString else { return }
        NSPasteboard.general.clearContents()
        if let previous { NSPasteboard.general.setString(previous, forType: .string) }
        #endif
    }

    private func copyToClipboard(_ url: URL) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }
}
