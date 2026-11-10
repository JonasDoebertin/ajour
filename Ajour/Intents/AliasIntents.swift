import AppIntents
import SimpleLoginKit

struct EnableAliasIntent: AppIntent {
    static let title: LocalizedStringResource = "Enable Alias"
    static let description = IntentDescription(
        "Enables an alias for a while and copies its address. Ajour turns it off again when the time is up."
    )

    @Parameter(title: "Alias")
    var alias: AliasEntity

    @Parameter(title: "Duration", default: .oneHour)
    var duration: EnableDuration

    @Dependency private var appModel: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Enable \(\.$alias) for \(\.$duration)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let enabled = try await explainingFailures {
            try await appModel.waitUntilLoaded()
            return try await appModel.enableAndCopy(aliasID: alias.id, email: alias.email, for: duration.aliasDuration)
        }
        return .result(
            value: enabled.email,
            dialog: "\(ActionDialog.enabled(enabled, duration: duration.aliasDuration))"
        )
    }
}

struct CreateRandomAliasIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Random Alias"
    static let description = IntentDescription(
        "Creates a random alias and copies its address, optionally turning it off after a while."
    )

    @Parameter(title: "Expiry", default: .never)
    var expiry: CreationExpiry

    @Dependency private var appModel: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Create a random alias with expiry \(\.$expiry)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let created = try await explainingFailures {
            try await appModel.waitUntilLoaded()
            return try await appModel.createRandomAliasAndCopy(expiringAfter: expiry.aliasDuration)
        }
        return .result(
            value: created.email,
            dialog: "\(ActionDialog.created(email: created.email, expiringAfter: expiry.aliasDuration))"
        )
    }
}

struct DisableAliasIntent: AppIntent {
    static let title: LocalizedStringResource = "Disable Alias"
    static let description = IntentDescription("Disables an alias now and ends its timer.")

    @Parameter(title: "Alias")
    var alias: AliasEntity

    @Dependency private var appModel: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Disable \(\.$alias)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await explainingFailures {
            try await appModel.waitUntilLoaded()
            try await appModel.disable(aliasID: alias.id, email: alias.email)
        }
        return .result(dialog: "\(ActionDialog.disabled(email: alias.email))")
    }
}
