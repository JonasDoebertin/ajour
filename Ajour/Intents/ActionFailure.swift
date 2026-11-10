import AppIntents
import Foundation

/// Carries the menu's words for a failure, so Spotlight and Shortcuts show what the menu would.
struct ActionFailure: LocalizedError, CustomLocalizedStringResourceConvertible {
    let message: String

    var errorDescription: String? { message }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// Rethrows failures in the menu's words. Cancellation passes through so the system can tell it apart.
@MainActor
func explainingFailures<Result>(_ body: @MainActor () async throws -> Result) async throws -> Result {
    do {
        return try await body()
    } catch let cancellation as CancellationError {
        throw cancellation
    } catch {
        throw ActionFailure(message: AppModel.userMessage(for: error))
    }
}
