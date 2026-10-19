import Foundation
@testable import SimpleLoginKit

final class InMemoryTimerStore: TimerStore, @unchecked Sendable {
    var records: [TimerRecord]
    var failLoad: Bool

    init(records: [TimerRecord] = [], failLoad: Bool = false) {
        self.records = records
        self.failLoad = failLoad
    }

    func load() throws -> [TimerRecord] {
        if failLoad { throw TimerStoreError.unreadable("test") }
        return records
    }

    func save(_ records: [TimerRecord]) throws {
        self.records = records
    }
}
