import Foundation

public struct AccountStats: Decodable, Equatable, Sendable {
    public let nbAlias: Int

    public init(nbAlias: Int) {
        self.nbAlias = nbAlias
    }
}

extension SimpleLoginAPI {
    public func stats() async throws -> AccountStats {
        try await send("GET", "/api/stats")
    }
}
