// Packages/ShareKit/Sources/ShareKit/ShareDestination.swift

import Foundation

/// Abstracts over a "place that captures can be uploaded to and shared from".
/// Conformances are responsible for: authenticating to the backend, writing the
/// file's bytes, and returning a URL that resolves over HTTPS GET with no auth
/// required (the captured asset must be publicly readable). Conformances must be
/// safe to call from any actor, hence the `Sendable` requirement.
public protocol ShareDestination: Sendable {
    /// Upload `file` under `key` and return the public URL.
    func upload(file: URL, key: String, contentType: String) async throws -> URL

    /// The public URL `upload(file:key:contentType:)` will return for `key`,
    /// known before the upload starts.
    nonisolated func publicURL(for key: String) -> URL

    /// Credential-free identity of the place `delete(key:)` acts on (provider, bucket,
    /// region/account, endpoint, path prefix). Stored with each upload record so a later
    /// delete is only sent to the same destination.
    nonisolated var destinationID: String { get }

    /// Delete an object by key. No-op if it doesn't exist.
    func delete(key: String) async throws

    /// Round-trip test: upload tiny file, fetch via public URL, delete.
    /// Throws if any step fails.
    func validateConfig() async throws
}

public extension ShareDestination {
    /// Fallback for test doubles; the real destinations derive it from their `ShareConfig`.
    nonisolated var destinationID: String { String(describing: type(of: self)) }
}
