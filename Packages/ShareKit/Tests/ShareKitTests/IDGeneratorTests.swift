// Packages/ShareKit/Tests/ShareKitTests/IDGeneratorTests.swift

import Testing
import Foundation
@testable import ShareKit

@Suite("IDGenerator")
struct IDGeneratorTests {
    @Test("generates 22-char IDs (≥ 128 bit)")
    func length() {
        #expect(IDGenerator.shortID().count == 22)
    }

    @Test("uses base62 charset only")
    func charset() {
        let allowed = Set("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let id = IDGenerator.shortID()
        #expect(id.allSatisfy { allowed.contains($0) })
    }

    @Test("produces unique IDs over 10k iterations")
    func uniqueness() {
        var seen = Set<String>()
        for _ in 0..<10_000 { seen.insert(IDGenerator.shortID()) }
        #expect(seen.count == 10_000)
    }
}
