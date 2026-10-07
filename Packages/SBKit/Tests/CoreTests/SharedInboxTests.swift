import Foundation
import Testing
@testable import Core

@Suite struct SharedInboxTests {
    @Test func readsMetadataDatesWithAnOffset() throws {
        let date = try #require(SharedInbox.parseMetadataDate("2026:09:14 00:41:07", offset: "+10:00"))
        #expect(date == Date(timeIntervalSince1970: 1_789_310_467))
    }

    @Test func readsISODates() throws {
        let date = try #require(SharedInbox.parseMetadataDate("2026-09-14T00:41:07+10:00", offset: nil))
        #expect(date == Date(timeIntervalSince1970: 1_789_310_467))
    }

    @Test func rejectsNonsense() {
        #expect(SharedInbox.parseMetadataDate("yesterday", offset: nil) == nil)
    }

    @Test func depositsAndLists() throws {
        // No App Group in tests: the inbox falls back to Application Support, so use a unique
        // file extension to find only what this test wrote.
        let marker = "t\(UInt32.random(in: 0...UInt32.max))"
        try SharedInbox.deposit(data: Data([0x00]), fileExtension: marker)
        try SharedInbox.deposit(data: Data([0x01]), fileExtension: marker)
        let mine = SharedInbox.pending().filter { $0.url.pathExtension == marker }
        #expect(mine.count == 2)
        for file in mine {
            try FileManager.default.removeItem(at: file.url)
        }
    }
}
