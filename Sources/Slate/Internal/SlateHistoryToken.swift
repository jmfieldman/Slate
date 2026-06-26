@preconcurrency import CoreData
import Foundation

struct SlateHistoryTokenStore {
    let storeURL: URL
    let tokenURL: URL

    private let fileManager: FileManager

    init(
        storeURL: URL,
        fileManager: FileManager = .default
    ) {
        self.storeURL = storeURL.standardizedFileURL
        self.tokenURL = Self.tokenURL(for: storeURL)
        self.fileManager = fileManager
    }

    static func tokenURL(for storeURL: URL) -> URL {
        storeURL.standardizedFileURL.appendingPathExtension("slate-history-token")
    }

    func load() throws -> NSPersistentHistoryToken? {
        guard fileManager.fileExists(atPath: tokenURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: tokenURL)
        return try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSPersistentHistoryToken.self,
            from: data
        )
    }

    func save(_ token: NSPersistentHistoryToken?) throws {
        guard let token else {
            guard fileManager.fileExists(atPath: tokenURL.path) else {
                return
            }
            try fileManager.removeItem(at: tokenURL)
            return
        }

        try fileManager.createDirectory(
            at: tokenURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )
        try data.write(to: tokenURL, options: [.atomic])
    }
}
