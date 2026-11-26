// Packages/ShareKit/Tests/ShareKitTests/UploadRecordStoreTests.swift

import Testing
import Foundation
@testable import ShareKit

extension UploadRecordStore {
    /// A store in its own temp folder, so tests never touch the real Application Support list.
    static func temporaryForTests(limit: Int = UploadRecordStore.defaultLimit) -> UploadRecordStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnippiUploadRecordTests-\(UUID().uuidString)", isDirectory: true)
        return UploadRecordStore(fileURL: dir.appendingPathComponent("CloudShareUploads.json"), limit: limit)
    }
}

@Suite("UploadRecordStore", .serialized)
@MainActor
struct UploadRecordStoreTests {
    actor FakeDestination: ShareDestination {
        nonisolated let destinationID: String
        private var failure: ShareError?
        private(set) var deletedKeys: [String] = []

        init(destinationID: String = "fake-dest", failure: ShareError? = nil) {
            self.destinationID = destinationID
            self.failure = failure
        }

        func setFailure(_ error: ShareError?) { failure = error }

        func upload(file: URL, key: String, contentType: String) async throws -> URL {
            URL(string: "https://fake/\(key)")!
        }
        nonisolated func publicURL(for key: String) -> URL { URL(string: "https://fake/\(key)")! }
        func delete(key: String) async throws {
            if let failure { throw failure }
            deletedKeys.append(key)
        }
        func validateConfig() async throws {}
    }

    private func permissions(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test("add stores newest first and survives a reload")
    func addAndReload() throws {
        let store = UploadRecordStore.temporaryForTests()
        store.add(key: "a.png", displayName: "A", destinationID: "d1")
        store.add(key: "b.png", displayName: "B", destinationID: "d1")

        #expect(store.records.map(\.key) == ["b.png", "a.png"])
        #expect(store.lastPersistenceError == nil)

        // ISO 8601 keeps whole seconds; everything else must round-trip exactly.
        let reloaded = UploadRecordStore(fileURL: store.fileURL)
        #expect(reloaded.records.map(\.id) == store.records.map(\.id))
        #expect(reloaded.records.map(\.key) == ["b.png", "a.png"])
        #expect(reloaded.records.map(\.displayName) == ["B", "A"])
        #expect(reloaded.records.map(\.destinationID) == ["d1", "d1"])
        for (loaded, original) in zip(reloaded.records, store.records) {
            #expect(abs(loaded.uploadedAt.timeIntervalSince(original.uploadedAt)) < 1)
        }
    }

    @Test("file is written with permissions 0600 and holds no URLs")
    func filePermissions() throws {
        let store = UploadRecordStore.temporaryForTests()
        store.add(key: "a.png", displayName: "A", destinationID: "d1")

        #expect(try permissions(of: store.fileURL) == 0o600)
        store.add(key: "b.png", displayName: "B", destinationID: "d1")
        #expect(try permissions(of: store.fileURL) == 0o600)

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.contains("https://"))
    }

    @Test("limit drops the oldest entries")
    func limitDropsOldest() {
        let store = UploadRecordStore.temporaryForTests(limit: 3)
        for index in 1...5 {
            store.add(key: "k\(index)", displayName: "\(index)", destinationID: "d1")
        }
        #expect(store.records.map(\.key) == ["k5", "k4", "k3"])
        #expect(UploadRecordStore(fileURL: store.fileURL, limit: 3).records.count == 3)
    }

    @Test("remove deletes only the matching entry and persists")
    func removeEntry() {
        let store = UploadRecordStore.temporaryForTests()
        let a = store.add(key: "a", displayName: "A", destinationID: "d1")
        store.add(key: "b", displayName: "B", destinationID: "d1")

        store.remove(id: a.id)
        #expect(store.records.map(\.key) == ["b"])
        #expect(UploadRecordStore(fileURL: store.fileURL).records.map(\.key) == ["b"])
    }

    @Test("successful delete removes the object and the entry")
    func deleteSuccess() async throws {
        let store = UploadRecordStore.temporaryForTests()
        let destination = FakeDestination()
        let record = store.add(key: "x.png", displayName: "X", destinationID: destination.destinationID)

        try await store.deleteUpload(record, using: destination)

        #expect(await destination.deletedKeys == ["x.png"])
        #expect(store.records.isEmpty)
        #expect(UploadRecordStore(fileURL: store.fileURL).records.isEmpty)
    }

    @Test("failed delete keeps the entry and reports the cause")
    func deleteFailureKeepsEntry() async {
        let store = UploadRecordStore.temporaryForTests()
        let destination = FakeDestination(failure: .invalidCredentials)
        let record = store.add(key: "x.png", displayName: "X", destinationID: destination.destinationID)

        await #expect(throws: UploadDeletionError.failed(.invalidCredentials)) {
            try await store.deleteUpload(record, using: destination)
        }
        #expect(store.records == [record])
    }

    @Test("delete against another destination sends nothing and keeps the entry")
    func deleteMismatch() async {
        let store = UploadRecordStore.temporaryForTests()
        let destination = FakeDestination(destinationID: "current")
        let record = store.add(key: "x.png", displayName: "X", destinationID: "old")

        await #expect(throws: UploadDeletionError.destinationMismatch) {
            try await store.deleteUpload(record, using: destination)
        }
        #expect(await destination.deletedKeys.isEmpty)
        #expect(store.records == [record])
    }

    @Test("delete all removes matching entries, skips others, keeps failures")
    func deleteAll() async {
        let store = UploadRecordStore.temporaryForTests()
        let destination = FakeDestination(destinationID: "current")
        store.add(key: "a", displayName: "A", destinationID: "current")
        let other = store.add(key: "b", displayName: "B", destinationID: "old")
        store.add(key: "c", displayName: "C", destinationID: "current")

        let summary = await store.deleteAllUploads(using: destination)
        #expect(summary.deleted == 2)
        #expect(summary.skippedOtherDestination == 1)
        #expect(summary.failed.isEmpty)
        #expect(store.records == [other])

        let failing = FakeDestination(destinationID: "old", failure: .network(underlying: "offline"))
        let second = await store.deleteAllUploads(using: failing)
        #expect(second.deleted == 0)
        #expect(second.failed[other.id] == .network(underlying: "offline"))
        #expect(store.records == [other])
    }

    @Test("coordinator records a successful upload with key and destination")
    func coordinatorRecordsUpload() async throws {
        let store = UploadRecordStore.temporaryForTests()
        let destination = FakeDestination(destinationID: "dest-1")
        let coord = ShareCoordinator(destination: destination, uploadRecords: store)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("record-\(UUID().uuidString).png")
        try Data([0]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try await coord.uploadReturningRecord(file: tmp, contentType: "image/png", displayName: "Shot")
        #expect(store.records == [result.record])
        #expect(result.record.destinationID == "dest-1")
        #expect(result.record.displayName == "Shot")
        #expect(result.url.lastPathComponent == result.record.key)
    }

    @Test("destination ID ignores credentials and URL prefix, tracks bucket and path prefix")
    func destinationIDFromConfig() {
        let base = ShareConfig(provider: .r2, urlPrefix: "https://a.example", accountID: "acc", bucket: "b1")
        let otherPrefix = ShareConfig(provider: .r2, urlPrefix: "https://b.example", accountID: "acc", bucket: "b1")
        let otherBucket = ShareConfig(provider: .r2, urlPrefix: "https://a.example", accountID: "acc", bucket: "b2")
        let withPath = ShareConfig(
            provider: .r2, urlPrefix: "https://a.example", bucket: "b1",
            fields: ["accountID": "acc", "pathPrefix": "/shots/"]
        )
        let withPathNormalized = ShareConfig(
            provider: .r2, urlPrefix: "https://a.example", bucket: "b1",
            fields: ["accountID": "acc", "pathPrefix": "shots"]
        )

        #expect(base.destinationID == otherPrefix.destinationID)
        #expect(base.destinationID != otherBucket.destinationID)
        #expect(base.destinationID != withPath.destinationID)
        #expect(withPath.destinationID == withPathNormalized.destinationID)
        #expect(R2Destination(config: base, accessKey: "k1", secretKey: "s1").destinationID
            == R2Destination(config: base, accessKey: "k2", secretKey: "s2").destinationID)
    }

    @Test("an unreadable list is moved aside, never overwritten by the next save")
    func unreadableListIsKept() throws {
        let store = UploadRecordStore.temporaryForTests()
        store.add(key: "a.png", displayName: "A", destinationID: "d1")
        try Data("not json".utf8).write(to: store.fileURL)

        let reloaded = UploadRecordStore(fileURL: store.fileURL)
        #expect(reloaded.records.isEmpty)
        #expect(reloaded.lastPersistenceError != nil)
        let folder = store.fileURL.deletingLastPathComponent()
        let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.contains(".unreadable-") }
        #expect(aside.count == 1)

        reloaded.add(key: "b.png", displayName: "B", destinationID: "d1")
        let again = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.contains(".unreadable-") }
        #expect(again.count == 1)
    }

    @Test("implausible keys from the file are never sent to the provider")
    func implausibleKeysAreRefused() async throws {
        let destination = FakeDestination()
        let store = UploadRecordStore.temporaryForTests()
        for bad in ["", "../x.png", "a/b.png", "a\u{0}b.png"] {
            let record = store.add(key: bad, displayName: "x", destinationID: destination.destinationID)
            await #expect(throws: UploadDeletionError.self) {
                try await store.deleteUpload(record, using: destination)
            }
        }
        #expect(await destination.deletedKeys.isEmpty)
        #expect(store.records.count == 4)
    }
}
