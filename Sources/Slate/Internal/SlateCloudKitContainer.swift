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
        var overrides: [UUID: ScopedLoadPersistentStoresOverride] = [:]
    }

    private final class AccountStatusProviderBox: @unchecked Sendable {
        let lock = NSLock()
        var providers: [UUID: ScopedAccountStatusProvider] = [:]
    }

    private final class EventObserverInstallerBox: @unchecked Sendable {
        let lock = NSLock()
        var installers: [UUID: ScopedEventObserverInstaller] = [:]
    }

    private final class StoreLoadCompletionAggregator: @unchecked Sendable {
        private let lock = NSLock()
        private var remainingCompletions: Int
        private var didComplete = false
        private let completion: (Error?) -> Void

        init(expectedCompletions: Int, completion: @escaping (Error?) -> Void) {
            remainingCompletions = max(expectedCompletions, 1)
            self.completion = completion
        }

        func complete(error: Error?) {
            let result: Error??
            lock.lock()
            if didComplete {
                result = nil
            } else if let error {
                didComplete = true
                result = .some(error)
            } else {
                remainingCompletions -= 1
                if remainingCompletions == 0 {
                    didComplete = true
                    result = .some(nil)
                } else {
                    result = nil
                }
            }
            lock.unlock()

            if let result {
                completion(result)
            }
        }
    }

    private struct ScopedLoadPersistentStoresOverride {
        let matches: @Sendable (NSPersistentCloudKitContainer) -> Bool
        let override: LoadPersistentStoresOverride
    }

    private struct ScopedAccountStatusProvider {
        let matches: @Sendable (String) -> Bool
        let provider: AccountStatusProvider
    }

    private struct ScopedEventObserverInstaller {
        let matches: @Sendable (NSPersistentCloudKitContainer) -> Bool
        let installer: EventObserverInstaller
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
        let privateStoreDescription: NSPersistentStoreDescription
        let sharedStoreDescription: NSPersistentStoreDescription?
        let storeDescriptions: [NSPersistentStoreDescription]

        var storeDescription: NSPersistentStoreDescription {
            privateStoreDescription
        }
    }

    static let privateStoreConfigurationName = "SlateCloudKitPrivateStore"
    static let sharedStoreConfigurationName = "SlateCloudKitSharedStore"

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
        case .cloudKitShared(let identifier):
            containerIdentifier = identifier
        case .local:
            throw SlateError.cloudKitUnavailable(mode: mode)
        }

        guard sourceDescription.type == NSSQLiteStoreType else {
            throw SlateError.cloudKitUnavailable(mode: mode)
        }

        let privateDescription = cloudKitDescription(
            cloning: sourceDescription,
            containerIdentifier: containerIdentifier
        )
        privateDescription.cloudKitContainerOptions?.databaseScope = .private

        let storeDescriptions: [NSPersistentStoreDescription]
        let sharedDescription: NSPersistentStoreDescription?
        switch mode {
        case .cloudKitMirrored:
            sharedDescription = nil
            storeDescriptions = [privateDescription]
        case .cloudKitShared:
            guard let privateURL = sourceDescription.url?.standardizedFileURL else {
                throw SlateError.cloudKitUnavailable(mode: mode)
            }
            model.setEntities(model.entities, forConfigurationName: privateStoreConfigurationName)
            model.setEntities(model.entities, forConfigurationName: sharedStoreConfigurationName)
            privateDescription.configuration = privateStoreConfigurationName

            let description = cloudKitDescription(
                cloning: sourceDescription,
                containerIdentifier: containerIdentifier
            )
            description.url = sharedStoreURL(forPrivateStoreURL: privateURL)
            description.configuration = sharedStoreConfigurationName
            description.cloudKitContainerOptions?.databaseScope = .shared
            sharedDescription = description
            storeDescriptions = [privateDescription, description]
        case .local:
            throw SlateError.cloudKitUnavailable(mode: mode)
        }

        let container = NSPersistentCloudKitContainer(name: name, managedObjectModel: model)
        container.persistentStoreDescriptions = storeDescriptions
        let accountContainer = shouldUseLiveAccountContainer ? CKContainer(identifier: containerIdentifier) : nil

        return BuildResult(
            container: container,
            accountContainer: accountContainer,
            accountContainerIdentifier: containerIdentifier,
            privateStoreDescription: privateDescription,
            sharedStoreDescription: sharedDescription,
            storeDescriptions: storeDescriptions
        )
    }

    static func sharedStoreURL(forPrivateStoreURL privateURL: URL) -> URL {
        privateURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(privateURL.lastPathComponent).slate-shared.sqlite")
            .standardizedFileURL
    }

    private static func cloudKitDescription(
        cloning sourceDescription: NSPersistentStoreDescription,
        containerIdentifier: String
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        description.url = sourceDescription.url
        description.type = sourceDescription.type
        description.configuration = sourceDescription.configuration
        description.isReadOnly = sourceDescription.isReadOnly
        description.timeout = sourceDescription.timeout
        description.shouldAddStoreAsynchronously = sourceDescription.shouldAddStoreAsynchronously
        description.shouldMigrateStoreAutomatically = sourceDescription.shouldMigrateStoreAutomatically
        description.shouldInferMappingModelAutomatically = sourceDescription.shouldInferMappingModelAutomatically
        for (key, value) in sourceDescription.options {
            description.setOption(value as NSObject?, forKey: key)
        }
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        return description
    }

    static func loadPersistentStores(
        for container: NSPersistentCloudKitContainer,
        completion: @escaping (Error?) -> Void
    ) {
        let aggregator = StoreLoadCompletionAggregator(
            expectedCompletions: container.persistentStoreDescriptions.count,
            completion: completion
        )

        loadOverrideBox.lock.lock()
        let override = loadOverrideBox.overrides.values.first { $0.matches(container) }?.override
        loadOverrideBox.lock.unlock()

        if let override {
            override(container) { error in
                aggregator.complete(error: error)
            }
            return
        }

        container.loadPersistentStores { _, error in
            aggregator.complete(error: error)
        }
    }

    static func accountStatus(
        for accountContainer: CKContainer?,
        forContainerIdentifier containerIdentifier: String,
        completion: @escaping @Sendable (AccountStatusResult) -> Void
    ) {
        accountStatusProviderBox.lock.lock()
        let provider = accountStatusProviderBox.providers.values
            .first { $0.matches(containerIdentifier) }?.provider
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
        let installer = eventObserverInstallerBox.installers.values
            .first { $0.matches(container) }?.installer
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
        let hasProvider = !accountStatusProviderBox.providers.isEmpty
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
        try withLoadPersistentStoresOverride(matching: { _ in true }, override, body)
    }

    static func withLoadPersistentStoresOverride<T>(
        matchingContainerIdentifier containerIdentifier: String,
        _ override: @escaping LoadPersistentStoresOverride,
        _ body: () throws -> T
    ) rethrows -> T {
        try withLoadPersistentStoresOverride(
            matching: { container in
                self.containerIdentifier(for: container) == containerIdentifier
            },
            override,
            body
        )
    }

    static func withLoadPersistentStoresOverride<T>(
        matchingContainerIdentifierPrefix prefix: String,
        _ override: @escaping LoadPersistentStoresOverride,
        _ body: () throws -> T
    ) rethrows -> T {
        try withLoadPersistentStoresOverride(
            matching: { container in
                self.containerIdentifier(for: container)?.hasPrefix(prefix) == true
            },
            override,
            body
        )
    }

    private static func withLoadPersistentStoresOverride<T>(
        matching matches: @escaping @Sendable (NSPersistentCloudKitContainer) -> Bool,
        _ override: @escaping LoadPersistentStoresOverride,
        _ body: () throws -> T
    ) rethrows -> T {
        let id = UUID()
        loadOverrideBox.lock.lock()
        loadOverrideBox.overrides[id] = ScopedLoadPersistentStoresOverride(
            matches: matches,
            override: override
        )
        loadOverrideBox.lock.unlock()
        defer {
            loadOverrideBox.lock.lock()
            loadOverrideBox.overrides.removeValue(forKey: id)
            loadOverrideBox.lock.unlock()
        }
        return try body()
    }

    static func withAccountStatusProviderOverride<T>(
        _ provider: @escaping AccountStatusProvider,
        _ body: () throws -> T
    ) rethrows -> T {
        try withAccountStatusProviderOverride(matching: { _ in true }, provider, body)
    }

    static func withAccountStatusProviderOverride<T>(
        matchingContainerIdentifierPrefix prefix: String,
        _ provider: @escaping AccountStatusProvider,
        _ body: () throws -> T
    ) rethrows -> T {
        try withAccountStatusProviderOverride(
            matching: { $0.hasPrefix(prefix) },
            provider,
            body
        )
    }

    private static func withAccountStatusProviderOverride<T>(
        matching matches: @escaping @Sendable (String) -> Bool,
        _ provider: @escaping AccountStatusProvider,
        _ body: () throws -> T
    ) rethrows -> T {
        let id = UUID()
        accountStatusProviderBox.lock.lock()
        accountStatusProviderBox.providers[id] = ScopedAccountStatusProvider(
            matches: matches,
            provider: provider
        )
        accountStatusProviderBox.lock.unlock()
        defer {
            accountStatusProviderBox.lock.lock()
            accountStatusProviderBox.providers.removeValue(forKey: id)
            accountStatusProviderBox.lock.unlock()
        }
        return try body()
    }

    static func withEventObserverInstallerOverride<T>(
        _ installer: @escaping EventObserverInstaller,
        _ body: () throws -> T
    ) rethrows -> T {
        try withEventObserverInstallerOverride(matching: { _ in true }, installer, body)
    }

    static func withEventObserverInstallerOverride<T>(
        matchingContainerIdentifierPrefix prefix: String,
        _ installer: @escaping EventObserverInstaller,
        _ body: () throws -> T
    ) rethrows -> T {
        try withEventObserverInstallerOverride(
            matching: { container in
                self.containerIdentifier(for: container)?.hasPrefix(prefix) == true
            },
            installer,
            body
        )
    }

    private static func withEventObserverInstallerOverride<T>(
        matching matches: @escaping @Sendable (NSPersistentCloudKitContainer) -> Bool,
        _ installer: @escaping EventObserverInstaller,
        _ body: () throws -> T
    ) rethrows -> T {
        let id = UUID()
        eventObserverInstallerBox.lock.lock()
        eventObserverInstallerBox.installers[id] = ScopedEventObserverInstaller(
            matches: matches,
            installer: installer
        )
        eventObserverInstallerBox.lock.unlock()
        defer {
            eventObserverInstallerBox.lock.lock()
            eventObserverInstallerBox.installers.removeValue(forKey: id)
            eventObserverInstallerBox.lock.unlock()
        }
        return try body()
    }

    private static func containerIdentifier(for container: NSPersistentCloudKitContainer) -> String? {
        container.persistentStoreDescriptions.first?.cloudKitContainerOptions?.containerIdentifier
    }

}
