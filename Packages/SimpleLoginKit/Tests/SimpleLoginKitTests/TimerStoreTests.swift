import Foundation
import Testing
@testable import SimpleLoginKit

struct TimerStoreTests {
    private let directory: URL
    private let fileURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimerStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("timers.json")
    }

    private func makeRecords() -> [TimerRecord] {
        [
            TimerRecord(
                aliasID: 1,
                email: "one@example.com",
                enabledAt: Date(timeIntervalSince1970: 1_700_000_000),
                expiresAt: Date(timeIntervalSince1970: 1_700_000_300),
                lastNotifiedActivityTimestamp: nil
            ),
            TimerRecord(
                aliasID: 2,
                email: "two@example.com",
                enabledAt: Date(timeIntervalSince1970: 1_700_001_000),
                expiresAt: Date(timeIntervalSince1970: 1_700_004_600),
                lastNotifiedActivityTimestamp: Date(timeIntervalSince1970: 1_700_002_000)
            ),
        ]
    }

    @Test func roundTripsRecords() throws {
        let store = FileTimerStore(fileURL: fileURL)
        let records = makeRecords()

        try store.save(records)

        #expect(try store.load() == records)
    }

    @Test func aTimerFileWithoutRefusalStillLoads() throws {
        let json = """
        [{"aliasID": 1, "email": "one@example.com", "enabledAt": "2023-11-14T22:13:20Z", "expiresAt": "2023-11-14T22:18:20Z"}]
        """
        try Data(json.utf8).write(to: fileURL)

        let records = try FileTimerStore(fileURL: fileURL).load()

        #expect(records.count == 1)
        #expect(records[0].refusalReportedAt == nil)
    }

    @Test func missingFileLoadsEmpty() throws {
        let store = FileTimerStore(fileURL: fileURL)

        #expect(try store.load().isEmpty)
    }

    @Test func corruptFileThrowsAndIsNotOverwritten() throws {
        let corrupt = Data("{not json".utf8)
        try corrupt.write(to: fileURL)
        let store = FileTimerStore(fileURL: fileURL)

        #expect(throws: TimerStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fileURL) == corrupt)
    }

    @Test func saveIsAtomic() throws {
        let store = FileTimerStore(fileURL: fileURL)

        try store.save(makeRecords())
        try store.save([])

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == ["timers.json"])
    }

    @Test func saveCreatesMissingParentDirectory() throws {
        let nested = directory.appendingPathComponent("nested/deeper/timers.json")
        let store = FileTimerStore(fileURL: nested)

        try store.save(makeRecords())

        #expect(try store.load() == makeRecords())
    }

    @Test func defaultURLLivesInApplicationSupportUnderBundleIdentifier() throws {
        let url = try FileTimerStore.defaultURL()

        #expect(url.lastPathComponent == "timers.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "de.dieserjonas.ajour")
        #expect(url.path.contains("Application Support"))
    }

    @Test func inMemoryStoreFailsLoadWhenRequested() {
        let store = InMemoryTimerStore(failLoad: true)

        #expect(throws: TimerStoreError.unreadable("test")) { try store.load() }
    }
}

struct AliasDurationTests {
    @Test func offersExactlyTheThreeDurations() {
        #expect(AliasDuration.allCases == [.fiveMinutes, .oneHour, .twentyFourHours])
        #expect(AliasDuration.allCases.map(\.seconds) == [300, 3600, 86400])
        #expect(AliasDuration.allCases.map(\.title) == ["5 Minutes", "1 Hour", "24 Hours"])
    }
}
