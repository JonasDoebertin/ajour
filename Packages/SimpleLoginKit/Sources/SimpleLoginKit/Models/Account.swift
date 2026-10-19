public struct UserInfo: Decodable, Equatable, Sendable {
    public let name: String
    public let email: String
    public let isPremium: Bool

    public init(name: String, email: String, isPremium: Bool) {
        self.name = name
        self.email = email
        self.isPremium = isPremium
    }
}
