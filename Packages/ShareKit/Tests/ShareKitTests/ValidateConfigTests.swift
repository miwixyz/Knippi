import Foundation
import Testing
@testable import ShareKit

/// Audit Q9 (21.11.): when the public check request failed outright (DNS, timeout, TLS),
/// the test file stayed in the bucket because `delete` was skipped.
@Suite("validateConfig cleanup")
struct ValidateConfigTests {
    actor RecordingDestination: ShareDestination {
        private(set) var deletedKeys: [String] = []
        func upload(file: URL, key: String, contentType: String) async throws -> URL {
            URL(string: "http://127.0.0.1:1/\(key)")!   // nothing listens: the GET fails
        }
        func delete(key: String) async throws { deletedKeys.append(key) }
        nonisolated func publicURL(for key: String) -> URL { URL(string: "http://127.0.0.1:1/\(key)")! }
    }

    @Test("the test file is deleted even when the public check can't connect")
    func deletesTestFileOnNetworkError() async throws {
        let destination = RecordingDestination()
        await #expect(throws: ShareError.publicAccessUnreachable) {
            try await destination.validateConfig()
        }
        #expect(await destination.deletedKeys.count == 1)
    }
}
