import Foundation

public protocol TimerStore: Sendable {
    func load() throws -> [TimerRecord]
    func save(_ records: [TimerRecord]) throws
}

public enum TimerStoreError: Error, Equatable {
    case unreadable(String)
}

public struct FileTimerStore: TimerStore {
    private static let bundleIdentifier = "de.doebertin.simplelogin-macos"
    private static let fileName = "timers.json"

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// A missing file means no timers. Any other failure throws and leaves the file untouched,
    /// so callers never mistake an unreadable file for an empty list and overwrite it.
    public func load() throws -> [TimerRecord] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            throw TimerStoreError.unreadable(error.localizedDescription)
        }

        do {
            return try Self.makeDecoder().decode([TimerRecord].self, from: data)
        } catch {
            throw TimerStoreError.unreadable(error.localizedDescription)
        }
    }

    public func save(_ records: [TimerRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.makeEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
