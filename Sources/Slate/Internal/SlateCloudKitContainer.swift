@preconcurrency import CoreData

enum SlateCloudKitContainer {
    typealias LoadPersistentStoresOverride = (
        NSPersistentCloudKitContainer,
        @escaping (Error?) -> Void
    ) -> Void

    private final class LoadOverrideBox: @unchecked Sendable {
        let lock = NSLock()
        var override: LoadPersistentStoresOverride?
    }

    private static let loadOverrideBox = LoadOverrideBox()

    struct BuildResult {
        let container: NSPersistentCloudKitContainer
        let storeDescription: NSPersistentStoreDescription
    }

    static func build(
        name: String,
        model: NSManagedObjectModel,
        sourceDescription: NSPersistentStoreDescription,
        mode: SlateStorageMode
    ) throws -> BuildResult {
        let containerIdentifier: String
        switch mode {
        case .cloudKitMirrored(let identifier):
            containerIdentifier = identifier
        case .cloudKitShared:
            throw SlateError.sharingUnavailable(mode: mode)
        case .local:
            throw SlateError.cloudKitUnavailable(mode: mode)
        }

        guard sourceDescription.type == NSSQLiteStoreType else {
            throw SlateError.cloudKitUnavailable(mode: mode)
        }

        let description = NSPersistentStoreDescription()
        description.url = sourceDescription.url
        description.type = sourceDescription.type
        description.shouldMigrateStoreAutomatically = sourceDescription.shouldMigrateStoreAutomatically
        description.shouldInferMappingModelAutomatically = sourceDescription.shouldInferMappingModelAutomatically
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        let container = NSPersistentCloudKitContainer(name: name, managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        return BuildResult(container: container, storeDescription: description)
    }

    static func loadPersistentStores(
        for container: NSPersistentCloudKitContainer,
        completion: @escaping (Error?) -> Void
    ) {
        loadOverrideBox.lock.lock()
        let override = loadOverrideBox.override
        loadOverrideBox.lock.unlock()

        if let override {
            override(container, completion)
            return
        }

        container.loadPersistentStores { _, error in
            completion(error)
        }
    }

    static func withLoadPersistentStoresOverride<T>(
        _ override: @escaping LoadPersistentStoresOverride,
        _ body: () throws -> T
    ) rethrows -> T {
        loadOverrideBox.lock.lock()
        loadOverrideBox.override = override
        loadOverrideBox.lock.unlock()
        defer {
            loadOverrideBox.lock.lock()
            loadOverrideBox.override = nil
            loadOverrideBox.lock.unlock()
        }
        return try body()
    }
}
