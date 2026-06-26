@preconcurrency import CloudKit
@preconcurrency import CoreData

enum SlateCloudKitContainer {
    typealias LoadPersistentStoresOverride = (
        NSPersistentCloudKitContainer,
        @escaping (Error?) -> Void
    ) -> Void
    typealias AccountStatusProvider = (
        String,
        @escaping @Sendable (AccountStatusResult) -> Void
    ) -> Void

    private final class LoadOverrideBox: @unchecked Sendable {
        let lock = NSLock()
        var override: LoadPersistentStoresOverride?
    }

    private final class AccountStatusProviderBox: @unchecked Sendable {
        let lock = NSLock()
        var provider: AccountStatusProvider?
    }

    private static let loadOverrideBox = LoadOverrideBox()
    private static let accountStatusProviderBox = AccountStatusProviderBox()

    struct AccountStatusResult: Sendable {
        let status: CKAccountStatus?
        let error: (any Error)?
    }

    struct BuildResult {
        let container: NSPersistentCloudKitContainer
        let accountContainer: CKContainer?
        let accountContainerIdentifier: String
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
        let accountContainer = shouldUseLiveAccountContainer ? CKContainer(identifier: containerIdentifier) : nil

        return BuildResult(
            container: container,
            accountContainer: accountContainer,
            accountContainerIdentifier: containerIdentifier,
            storeDescription: description
        )
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

    static func accountStatus(
        for accountContainer: CKContainer?,
        forContainerIdentifier containerIdentifier: String,
        completion: @escaping @Sendable (AccountStatusResult) -> Void
    ) {
        accountStatusProviderBox.lock.lock()
        let provider = accountStatusProviderBox.provider
        accountStatusProviderBox.lock.unlock()

        if let provider {
            provider(containerIdentifier, completion)
            return
        }

        guard shouldUseLiveAccountContainer, let container = accountContainer else {
            completion(AccountStatusResult(status: .couldNotDetermine, error: nil))
            return
        }

        container.accountStatus { status, error in
            completion(AccountStatusResult(status: status, error: error))
        }
    }

    private static var shouldUseLiveAccountContainer: Bool {
        accountStatusProviderBox.lock.lock()
        let hasProvider = accountStatusProviderBox.provider != nil
        accountStatusProviderBox.lock.unlock()
        if hasProvider {
            return false
        }

        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        if processInfo.processName.contains("xctest")
            || processInfo.processName.contains("swiftpm-testing-helper")
        {
            return false
        }
        if processInfo.arguments.contains(where: {
            $0.contains(".xctest") || $0.contains("swiftpm-testing-helper")
        }) {
            return false
        }
        return true
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

    static func withAccountStatusProviderOverride<T>(
        _ provider: @escaping AccountStatusProvider,
        _ body: () throws -> T
    ) rethrows -> T {
        accountStatusProviderBox.lock.lock()
        accountStatusProviderBox.provider = provider
        accountStatusProviderBox.lock.unlock()
        defer {
            accountStatusProviderBox.lock.lock()
            accountStatusProviderBox.provider = nil
            accountStatusProviderBox.lock.unlock()
        }
        return try body()
    }

}
