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
    typealias EventObserverInstaller = (
        NSPersistentCloudKitContainer,
        @escaping @Sendable (EventSnapshot) -> Void
    ) -> EventObserverToken

    private final class LoadOverrideBox: @unchecked Sendable {
        let lock = NSLock()
        var override: LoadPersistentStoresOverride?
    }

    private final class AccountStatusProviderBox: @unchecked Sendable {
        let lock = NSLock()
        var provider: AccountStatusProvider?
    }

    private final class EventObserverInstallerBox: @unchecked Sendable {
        let lock = NSLock()
        var installer: EventObserverInstaller?
    }

    private final class NotificationObserverBox: @unchecked Sendable {
        let observer: NSObjectProtocol

        init(_ observer: NSObjectProtocol) {
            self.observer = observer
        }
    }

    private static let loadOverrideBox = LoadOverrideBox()
    private static let accountStatusProviderBox = AccountStatusProviderBox()
    private static let eventObserverInstallerBox = EventObserverInstallerBox()

    struct AccountStatusResult: Sendable {
        let status: CKAccountStatus?
        let error: (any Error)?
    }

    struct EventSnapshot: Sendable {
        let identifier: UUID
        let type: NSPersistentCloudKitContainer.EventType
        let endDate: Date?
        let error: (any Error)?

        init(
            identifier: UUID,
            type: NSPersistentCloudKitContainer.EventType,
            endDate: Date?,
            error: (any Error)?
        ) {
            self.identifier = identifier
            self.type = type
            self.endDate = endDate
            self.error = error
        }

        init(_ event: NSPersistentCloudKitContainer.Event) {
            self.init(
                identifier: event.identifier,
                type: event.type,
                endDate: event.endDate,
                error: event.error
            )
        }
    }

    final class EventObserverToken: @unchecked Sendable {
        private let lock = NSLock()
        private var invalidateHandler: (@Sendable () -> Void)?

        init(_ invalidate: @escaping @Sendable () -> Void) {
            invalidateHandler = invalidate
        }

        func invalidate() {
            let handler: (@Sendable () -> Void)?
            lock.lock()
            handler = invalidateHandler
            invalidateHandler = nil
            lock.unlock()
            handler?()
        }
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

    static func observeEvents(
        for container: NSPersistentCloudKitContainer,
        handler: @escaping @Sendable (EventSnapshot) -> Void
    ) -> EventObserverToken {
        eventObserverInstallerBox.lock.lock()
        let installer = eventObserverInstallerBox.installer
        eventObserverInstallerBox.lock.unlock()

        if let installer {
            return installer(container, handler)
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            handler(EventSnapshot(event))
        }
        let observerBox = NotificationObserverBox(observer)

        return EventObserverToken {
            NotificationCenter.default.removeObserver(observerBox.observer)
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

    static func withEventObserverInstallerOverride<T>(
        _ installer: @escaping EventObserverInstaller,
        _ body: () throws -> T
    ) rethrows -> T {
        eventObserverInstallerBox.lock.lock()
        eventObserverInstallerBox.installer = installer
        eventObserverInstallerBox.lock.unlock()
        defer {
            eventObserverInstallerBox.lock.lock()
            eventObserverInstallerBox.installer = nil
            eventObserverInstallerBox.lock.unlock()
        }
        return try body()
    }

}
