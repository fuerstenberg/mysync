import Foundation

public protocol ConfigStoring: Sendable {
    func load() throws -> AppConfig
    func save(_ config: AppConfig) throws
}

/// Speichert die Konfiguration als JSON-Datei.
public struct ConfigStore: ConfigStoring {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/mysync/config.json`
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("mysync", isDirectory: true).appendingPathComponent("config.json")
    }

    public static let `default` = ConfigStore(fileURL: defaultURL)

    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfig()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppConfig.self, from: data)
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Speicher im Arbeitsspeicher, z. B. für Tests und Vorschauen.
public final class InMemoryConfigStore: ConfigStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppConfig
    public private(set) var saveCount = 0

    public init(_ config: AppConfig = AppConfig()) {
        self.stored = config
    }

    public func load() throws -> AppConfig {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ config: AppConfig) throws {
        lock.lock(); defer { lock.unlock() }
        stored = config
        saveCount += 1
    }
}
