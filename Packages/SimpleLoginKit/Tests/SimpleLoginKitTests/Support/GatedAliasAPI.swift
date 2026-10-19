import Foundation
@testable import SimpleLoginKit

/// Holds every `alias(id:)` request at a closed gate, so tests can act while a request is in flight.
final class GatedAliasAPI: AliasAPI, @unchecked Sendable {
    let base: FakeAliasAPI
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(base: FakeAliasAPI) {
        self.base = base
    }

    func alias(id: Int) async throws -> Alias {
        await passGate()
        return try await base.alias(id: id)
    }

    func toggle(aliasID: Int) async throws -> Bool {
        try await base.toggle(aliasID: aliasID)
    }

    func waitUntilHolding(_ count: Int) async {
        while lock.withLock({ waiters.count }) < count {
            await Task.yield()
        }
    }

    func open() {
        let released = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        released.forEach { $0.resume() }
    }

    private func passGate() async {
        await withCheckedContinuation { continuation in
            let passesImmediately = lock.withLock {
                if !isOpen { waiters.append(continuation) }
                return isOpen
            }
            if passesImmediately { continuation.resume() }
        }
    }
}
