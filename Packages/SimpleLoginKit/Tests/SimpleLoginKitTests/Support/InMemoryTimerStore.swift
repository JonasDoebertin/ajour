import Foundation
@testable import SimpleLoginKit

final class InMemoryTimerStore: TimerStore, @unchecked Sendable {
    var records: [TimerRecord]
    var failLoad: Bool
    var failSave = false

    init(records: [TimerRecord] = [], failLoad: Bool = false) {
        self.records = records
        self.failLoad = failLoad
    }

    func load() throws -> [TimerRecord] {
        if failLoad { throw TimerStoreError.unreadable("test") }
        return records
    }

    func save(_ records: [TimerRecord]) throws {
        if failSave { throw TimerStoreError.unreadable("test") }
        self.records = records
    }
}
