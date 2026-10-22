import Foundation

/// An error message shown as a title with an optional detail, split after the first sentence.
struct ProblemMessage: Equatable {
    let title: String
    let detail: String?

    init(_ message: String) {
        guard let sentenceEnd = message.range(of: ". ") else {
            title = message
            detail = nil
            return
        }
        title = String(message[..<message.index(before: sentenceEnd.upperBound)])
        let rest = message[sentenceEnd.upperBound...].trimmingCharacters(in: .whitespaces)
        detail = rest.isEmpty ? nil : rest
    }
}
