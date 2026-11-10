import AppIntents
import SimpleLoginKit

struct AliasEntity: AppEntity {
    let id: Int
    let email: String
    let note: String?

    init(_ alias: Alias) {
        id = alias.id
        email = alias.email
        note = alias.note
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Alias"
    static let defaultQuery = AliasEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(email)", subtitle: note.map { "\($0)" })
    }
}

struct AliasEntityQuery: EntityStringQuery {
    @Dependency private var appModel: AppModel

    @MainActor
    func suggestedEntities() async throws -> [AliasEntity] {
        try await explainingFailures {
            try await appModel.waitUntilLoaded()
            return try await AliasLookup(appModel: appModel).suggestions().map(AliasEntity.init)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [AliasEntity] {
        try await explainingFailures {
            try await appModel.waitUntilLoaded()
            return try await AliasLookup(appModel: appModel).search(string).map(AliasEntity.init)
        }
    }

    @MainActor
    func entities(for identifiers: [Int]) async throws -> [AliasEntity] {
        try await explainingFailures {
            try await appModel.waitUntilLoaded()
            return try await AliasLookup(appModel: appModel).aliases(ids: identifiers).map(AliasEntity.init)
        }
    }
}
