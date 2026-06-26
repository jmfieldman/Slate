import CloudKit
import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@Suite
struct SlateSharingTests {
    @Test
    func shareAndParticipantConstructAndCompareByValue() throws {
        let owner = SlateParticipant(
            displayName: "Owner",
            role: .owner,
            permission: .readWrite,
            acceptanceStatus: .accepted
        )
        let participant = SlateParticipant(
            displayName: "Reader",
            role: .privateUser,
            permission: .readOnly,
            acceptanceStatus: .pending
        )
        let url = URL(string: "https://example.com/share")!
        let share = SlateShare(
            url: url,
            title: "Shared Slate",
            owner: owner,
            participants: [participant],
            currentUserPermission: .readWrite
        )

        #expect(owner == SlateParticipant(
            displayName: "Owner",
            role: .owner,
            permission: .readWrite,
            acceptanceStatus: .accepted
        ))
        #expect(participant != owner)
        #expect(share == SlateShare(
            url: url,
            title: "Shared Slate",
            owner: owner,
            participants: [participant],
            currentUserPermission: .readWrite
        ))
        #expect(share != SlateShare(
            url: url,
            title: "Different Slate",
            owner: owner,
            participants: [participant],
            currentUserPermission: .readWrite
        ))
    }

    @Test
    func sharingEnumsExposeApprovedCases() {
        let permissions: [SlateSharePermission] = [.unknown, .none, .readOnly, .readWrite]
        let roles: [SlateShareRole] = [.unknown, .owner, .privateUser, .publicUser, .administrator]
        let acceptanceStatuses: [SlateShareAcceptance] = [.unknown, .pending, .accepted, .removed]

        #expect(permissions.count == 4)
        #expect(Set(permissions.map(String.init(describing:))).count == permissions.count)
        #expect(roles.count == 5)
        #expect(Set(roles.map(String.init(describing:))).count == roles.count)
        #expect(acceptanceStatuses.count == 4)
        #expect(Set(acceptanceStatuses.map(String.init(describing:))).count == acceptanceStatuses.count)
    }

    @Test(arguments: [
        (CKShare.ParticipantPermission.unknown, SlateSharePermission.unknown),
        (CKShare.ParticipantPermission.none, SlateSharePermission.none),
        (CKShare.ParticipantPermission.readOnly, SlateSharePermission.readOnly),
        (CKShare.ParticipantPermission.readWrite, SlateSharePermission.readWrite),
    ])
    func mapsKnownCloudKitPermissions(
        cloudKitPermission: CKShare.ParticipantPermission,
        slatePermission: SlateSharePermission
    ) {
        #expect(SlateSharePermission(cloudKitPermission: cloudKitPermission) == slatePermission)
    }

    @Test(arguments: [
        (CKShare.ParticipantRole.unknown, SlateShareRole.unknown),
        (CKShare.ParticipantRole.owner, SlateShareRole.owner),
        (CKShare.ParticipantRole.privateUser, SlateShareRole.privateUser),
        (CKShare.ParticipantRole.publicUser, SlateShareRole.publicUser),
    ])
    func mapsKnownCloudKitRoles(
        cloudKitRole: CKShare.ParticipantRole,
        slateRole: SlateShareRole
    ) {
        #expect(SlateShareRole(cloudKitRole: cloudKitRole) == slateRole)
    }

    @Test
    func mapsCloudKitAdministratorRole() throws {
        let administratorRole = try #require(CKShare.ParticipantRole(rawValue: 2))

        #expect(SlateShareRole(cloudKitRole: administratorRole) == .administrator)
    }

    @Test(arguments: [
        (CKShare.ParticipantAcceptanceStatus.unknown, SlateShareAcceptance.unknown),
        (CKShare.ParticipantAcceptanceStatus.pending, SlateShareAcceptance.pending),
        (CKShare.ParticipantAcceptanceStatus.accepted, SlateShareAcceptance.accepted),
        (CKShare.ParticipantAcceptanceStatus.removed, SlateShareAcceptance.removed),
    ])
    func mapsKnownCloudKitAcceptanceStatuses(
        cloudKitAcceptanceStatus: CKShare.ParticipantAcceptanceStatus,
        slateAcceptance: SlateShareAcceptance
    ) {
        #expect(SlateShareAcceptance(cloudKitAcceptanceStatus: cloudKitAcceptanceStatus) == slateAcceptance)
    }

    @Test
    func mapsUnknownCloudKitStatesToUnknown() throws {
        let futurePermission = try #require(CKShare.ParticipantPermission(rawValue: 999))
        let futureRole = try #require(CKShare.ParticipantRole(rawValue: 999))
        let futureAcceptanceStatus = try #require(CKShare.ParticipantAcceptanceStatus(rawValue: 999))

        #expect(SlateSharePermission(cloudKitPermission: futurePermission) == .unknown)
        #expect(SlateShareRole(cloudKitRole: futureRole) == .unknown)
        #expect(SlateShareAcceptance(cloudKitAcceptanceStatus: futureAcceptanceStatus) == .unknown)
    }

    @Test
    func shareAndParticipantCanBeCapturedBySendableClosure() throws {
        let participant = SlateParticipant(
            displayName: nil,
            role: .administrator,
            permission: .readWrite,
            acceptanceStatus: .accepted
        )
        let share = SlateShare(
            url: URL(string: "https://example.com/admin-share")!,
            title: nil,
            owner: participant,
            participants: [participant],
            currentUserPermission: .readWrite
        )

        let capture: @Sendable () -> SlateShare = {
            #expect(participant.role == .administrator)
            return share
        }

        #expect(capture() == share)
    }

    @Test
    func localSharingGateThrowsSharingUnavailable() throws {
        let slate = Slate<TestSchema>(
            storeURL: nil,
            storeType: NSInMemoryStoreType,
            storageMode: .local
        )

        #expect(throws: SlateError.sharingUnavailable(mode: .local)) {
            _ = try slate.sharing
        }
    }

    @Test
    func cloudKitMirroredSharingGateThrowsSharingUnavailable() throws {
        let mode = SlateStorageMode.cloudKitMirrored(containerIdentifier: "iCloud.com.example.mirrored-sharing")
        let slate = Slate<TestCloudKitRuntimeSchema>(
            storeURL: nil,
            storeType: NSSQLiteStoreType,
            storageMode: mode
        )

        #expect(throws: SlateError.sharingUnavailable(mode: mode)) {
            _ = try slate.sharing
        }
    }

    @Test
    func cloudKitSharedSharingGateReturnsSendableFacadeShellAfterConfigure() throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingFacadeGate")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let slate = Slate<TestCloudKitRuntimeSchema>(
            storeURL: directory.appendingPathComponent("Private.sqlite"),
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitShared(containerIdentifier: "iCloud.com.example.facade-gate")
        )
        try configureWithSuccessfulCloudKitLoad(slate)

        let sharing = try slate.sharing
        let capture: @Sendable () -> SlateSharing = {
            sharing
        }

        #expect(Mirror(reflecting: capture()).displayStyle == .struct)
        #expect(Mirror(reflecting: sharing).children.count == 1)
    }

    @Test
    func sprintSevenDoesNotExposeSchemaInitializationOrShareLifecycleAPI() throws {
        let sourceText = try slateSourceText()
        let forbiddenTokens = [
            "initializeCloudKitSchema",
            "func share(",
            "func share<",
            "func share (",
            "func prepareShare",
            "func persist",
            "func stopSharing",
            "func acceptShare",
            "func lookupParticipants",
            "CKShare(",
        ]

        for token in forbiddenTokens {
            #expect(!sourceText.contains(token), "Unexpected Sprint 08 sharing surface found: \(token)")
        }
    }

    @Test
    func cloudKitMirroredBuildProducesSinglePrivateDescription() throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingMirroredBuild")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let sourceDescription = sqliteDescription(
            url: directory.appendingPathComponent("Private.sqlite")
        )

        let result = try SlateCloudKitContainer.build(
            name: TestCloudKitRuntimeSchema.schemaIdentifier,
            model: TestCloudKitRuntimeSchema.makeManagedObjectModel(),
            sourceDescription: sourceDescription,
            mode: .cloudKitMirrored(containerIdentifier: "iCloud.com.example")
        )

        #expect(result.storeDescriptions.count == 1)
        #expect(result.sharedStoreDescription == nil)
        let description = try #require(result.storeDescriptions.first)
        #expect(description === result.privateStoreDescription)
        #expect(description === result.storeDescription)
        #expect(description.url == sourceDescription.url)
        #expect(description.configuration == sourceDescription.configuration)
        #expect(description.cloudKitContainerOptions?.databaseScope == .private)
        assertCloudKitStoreOptionsEnabled(description)
        #expect(sourceDescription.cloudKitContainerOptions == nil)
        #expect(sourceDescription.options[NSPersistentHistoryTrackingKey] == nil)
        #expect(sourceDescription.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] == nil)
    }

    @Test
    func cloudKitSharedBuildProducesPrivateAndSharedDescriptions() throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingSharedBuild")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let privateURL = directory.appendingPathComponent("Private.sqlite")
        let sourceDescription = sqliteDescription(url: privateURL)
        let model = try TestCloudKitRuntimeSchema.makeManagedObjectModel()
        let originalEntityNames = Set(model.entities.map(\.name))

        let result = try SlateCloudKitContainer.build(
            name: TestCloudKitRuntimeSchema.schemaIdentifier,
            model: model,
            sourceDescription: sourceDescription,
            mode: .cloudKitShared(containerIdentifier: "iCloud.com.example")
        )

        #expect(result.container.persistentStoreDescriptions.count == 2)
        #expect(result.storeDescriptions.count == 2)
        let privateDescription = result.privateStoreDescription
        let sharedDescription = try #require(result.sharedStoreDescription)
        #expect(privateDescription !== sharedDescription)
        #expect(result.storeDescriptions.map(ObjectIdentifier.init) == [
            ObjectIdentifier(privateDescription),
            ObjectIdentifier(sharedDescription),
        ])

        #expect(privateDescription.url == privateURL)
        #expect(privateDescription.configuration == SlateCloudKitContainer.privateStoreConfigurationName)
        #expect(privateDescription.cloudKitContainerOptions?.databaseScope == .private)
        assertCloudKitStoreOptionsEnabled(privateDescription)

        let expectedSharedURL = SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: privateURL.standardizedFileURL)
        #expect(sharedDescription.url == expectedSharedURL)
        #expect(sharedDescription.url != privateURL)
        #expect(sharedDescription.configuration == SlateCloudKitContainer.sharedStoreConfigurationName)
        #expect(sharedDescription.cloudKitContainerOptions?.databaseScope == .shared)
        assertCloudKitStoreOptionsEnabled(sharedDescription)

        let privateConfigurationEntities = try #require(
            model.entities(forConfigurationName: SlateCloudKitContainer.privateStoreConfigurationName)
        )
        let sharedConfigurationEntities = try #require(
            model.entities(forConfigurationName: SlateCloudKitContainer.sharedStoreConfigurationName)
        )
        #expect(Set(privateConfigurationEntities.map(\.name)) == originalEntityNames)
        #expect(Set(sharedConfigurationEntities.map(\.name)) == originalEntityNames)

        #expect(sourceDescription.configuration == nil)
        #expect(sourceDescription.cloudKitContainerOptions == nil)
        #expect(sourceDescription.options[NSPersistentHistoryTrackingKey] == nil)
        #expect(sourceDescription.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] == nil)
    }

    @Test
    func cloudKitSharedConfigureOpensOneOwnerAndWaitsForBothStoreLoads() throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingOwnerOpen")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let mode = SlateStorageMode.cloudKitShared(containerIdentifier: "iCloud.com.example.shared-open")
        let slate = Slate<TestCloudKitRuntimeSchema>(
            storeURL: directory.appendingPathComponent("Private.sqlite"),
            storeType: NSSQLiteStoreType,
            storageMode: mode
        )
        let load = CapturedCloudKitLoad()

        try configureWithCapturedCloudKitLoad(slate, load: load)

        let owner = try slateStoreOwner(for: slate)
        let container = try load.requireCapturedContainer()
        #expect(owner.storageMode == mode)
        #expect(owner.cloudKitContainer === container)
        #expect(owner.coordinator === container.persistentStoreCoordinator)
        #expect(container.persistentStoreDescriptions.count == 2)
        let writerMergePolicy = try #require(owner.writerContext.mergePolicy as? NSMergePolicy)
        #expect(writerMergePolicy.mergeType == .mergeByPropertyObjectTrumpMergePolicyType)
        expectLoading(owner)

        try load.completeSuccessfully()
        expectLoading(owner)

        try load.completeSuccessfully()
        expectLoaded(owner)
    }

    @Test(arguments: [0, 1])
    func cloudKitSharedConfigureFailsWhenEitherStoreLoadFails(successfulCompletionsBeforeFailure: Int) throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingOwnerLoadFailure")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let mode = SlateStorageMode.cloudKitShared(
            containerIdentifier: "iCloud.com.example.shared-failure.\(successfulCompletionsBeforeFailure)"
        )
        let slate = Slate<TestCloudKitRuntimeSchema>(
            storeURL: directory.appendingPathComponent("Private.sqlite"),
            storeType: NSSQLiteStoreType,
            storageMode: mode
        )
        let load = CapturedCloudKitLoad()
        let expectedError = SlateError.coreData("store \(successfulCompletionsBeforeFailure) failed")

        try configureWithCapturedCloudKitLoad(slate, load: load)
        let owner = try slateStoreOwner(for: slate)
        for _ in 0..<successfulCompletionsBeforeFailure {
            try load.completeSuccessfully()
            expectLoading(owner)
        }

        try load.complete(error: expectedError)
        expectFailed(owner, expectedError: expectedError)
    }

    @Test
    func cloudKitSharedRegistryReusesPrivateURLIdentityAndRejectsModeOrSchemaMismatch() throws {
        let sameModeDirectory = try temporaryDirectory(prefix: "SlateSharingSameModeReuse")
        defer {
            try? FileManager.default.removeItem(at: sameModeDirectory)
        }
        let sameModeURL = sameModeDirectory.appendingPathComponent("Private.sqlite")
        let sameMode = SlateStorageMode.cloudKitShared(containerIdentifier: "iCloud.com.example.same-mode")
        let first = Slate<TestCloudKitRuntimeSchema>(
            storeURL: sameModeURL,
            storeType: NSSQLiteStoreType,
            storageMode: sameMode
        )
        try configureWithSuccessfulCloudKitLoad(first)

        let second = Slate<TestCloudKitRuntimeSchema>(
            storeURL: sameModeURL,
            storeType: NSSQLiteStoreType,
            storageMode: sameMode
        )
        try second.configure()

        #expect(try slateStoreOwner(for: first) === slateStoreOwner(for: second))

        let modeMismatchDirectory = try temporaryDirectory(prefix: "SlateSharingModeMismatch")
        defer {
            try? FileManager.default.removeItem(at: modeMismatchDirectory)
        }
        let modeMismatchURL = modeMismatchDirectory.appendingPathComponent("Private.sqlite")
        let mirrored = Slate<TestCloudKitRuntimeSchema>(
            storeURL: modeMismatchURL,
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitMirrored(containerIdentifier: "iCloud.com.example.mode-mismatch")
        )
        try configureWithSuccessfulCloudKitLoad(mirrored)

        let shared = Slate<TestCloudKitRuntimeSchema>(
            storeURL: modeMismatchURL,
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitShared(containerIdentifier: "iCloud.com.example.mode-mismatch")
        )
        #expect(throws: SlateError.incompatibleStore(modeMismatchURL.standardizedFileURL)) {
            try shared.configure()
        }

        let schemaMismatchDirectory = try temporaryDirectory(prefix: "SlateSharingSchemaMismatch")
        defer {
            try? FileManager.default.removeItem(at: schemaMismatchDirectory)
        }
        let schemaMismatchURL = schemaMismatchDirectory.appendingPathComponent("Private.sqlite")
        let runtimeSchemaSlate = Slate<TestCloudKitRuntimeSchema>(
            storeURL: schemaMismatchURL,
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitShared(containerIdentifier: "iCloud.com.example.schema-mismatch")
        )
        try configureWithSuccessfulCloudKitLoad(runtimeSchemaSlate)

        let otherSchemaSlate = Slate<TestCloudKitSchema>(
            storeURL: schemaMismatchURL,
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitShared(containerIdentifier: "iCloud.com.example.schema-mismatch")
        )
        #expect(throws: SlateError.incompatibleStore(schemaMismatchURL.standardizedFileURL)) {
            try otherSchemaSlate.configure()
        }
    }

    @Test
    func sharedStoreURLIsStableAdjacentAndAvoidsSQLiteSidecarCollisions() throws {
        let directory = URL(fileURLWithPath: "/tmp/slate-sharing-url-test")
        let privateURL = directory.appendingPathComponent("Private.sqlite")

        let firstURL = SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: privateURL)
        let secondURL = SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: privateURL)

        #expect(firstURL == secondURL)
        #expect(firstURL.deletingLastPathComponent() == privateURL.deletingLastPathComponent())
        #expect(firstURL != privateURL)
        #expect(firstURL != URL(fileURLWithPath: privateURL.path + "-wal"))
        #expect(firstURL != URL(fileURLWithPath: privateURL.path + "-shm"))
        #expect(firstURL.lastPathComponent.hasSuffix("-wal") == false)
        #expect(firstURL.lastPathComponent.hasSuffix("-shm") == false)

        let walNamedPrivateURL = URL(fileURLWithPath: privateURL.path + "-wal")
        let derivedFromWalName = SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: walNamedPrivateURL)
        #expect(derivedFromWalName != walNamedPrivateURL)
        #expect(derivedFromWalName.lastPathComponent.hasSuffix("-wal") == false)
        #expect(derivedFromWalName.lastPathComponent.hasSuffix("-shm") == false)
    }

    @Test
    func cloudKitSharedBuildRejectsInMemoryStoreType() throws {
        let inMemoryDescription = NSPersistentStoreDescription()
        inMemoryDescription.type = NSInMemoryStoreType
        let sharedMode = SlateStorageMode.cloudKitShared(containerIdentifier: "iCloud.com.example")

        #expect(throws: SlateError.cloudKitUnavailable(mode: sharedMode)) {
            try SlateCloudKitContainer.build(
                name: TestCloudKitRuntimeSchema.schemaIdentifier,
                model: TestCloudKitRuntimeSchema.makeManagedObjectModel(),
                sourceDescription: inMemoryDescription,
                mode: sharedMode
            )
        }
    }
}

private func sqliteDescription(url: URL) -> NSPersistentStoreDescription {
    let description = NSPersistentStoreDescription()
    description.type = NSSQLiteStoreType
    description.url = url
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = true
    return description
}

private func temporaryDirectory(prefix: String) throws -> URL {
    let directory = URL(
        fileURLWithPath: NSTemporaryDirectory(),
        isDirectory: true
    )
    .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func slateSourceText() throws -> String {
    let fileManager = FileManager.default
    var directory = URL(fileURLWithPath: #filePath)
    while directory.path != "/" {
        let sourcesDirectory = directory.appendingPathComponent("Sources/Slate", isDirectory: true)
        if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path),
           fileManager.fileExists(atPath: sourcesDirectory.path) {
            return try swiftSourceText(in: sourcesDirectory)
        }
        directory.deleteLastPathComponent()
    }

    throw NSError(
        domain: "SlateSharingTests",
        code: -6,
        userInfo: [NSLocalizedDescriptionKey: "Could not locate package root from \(#filePath)"]
    )
}

private func swiftSourceText(in directory: URL) throws -> String {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        throw NSError(
            domain: "SlateSharingTests",
            code: -7,
            userInfo: [NSLocalizedDescriptionKey: "Could not enumerate \(directory.path)"]
        )
    }

    let files = enumerator.compactMap { item -> URL? in
        guard let url = item as? URL, url.pathExtension == "swift" else {
            return nil
        }
        return url
    }
    .sorted { $0.path < $1.path }

    return try files
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
}

private func configureWithCapturedCloudKitLoad<Schema: SlateSchema>(
    _ slate: Slate<Schema>,
    load: CapturedCloudKitLoad
) throws {
    let containerIdentifier = try cloudKitContainerIdentifier(for: slate)
    try SlateCloudKitContainer.withLoadPersistentStoresOverride(
        matchingContainerIdentifier: containerIdentifier,
        { container, completion in
            load.capture(container: container, completion: completion)
        }
    ) {
        try slate.configure()
    }
    try load.requireCaptured()
}

private func configureWithSuccessfulCloudKitLoad<Schema: SlateSchema>(_ slate: Slate<Schema>) throws {
    let containerIdentifier = try cloudKitContainerIdentifier(for: slate)
    try SlateCloudKitContainer.withLoadPersistentStoresOverride(
        matchingContainerIdentifier: containerIdentifier,
        { container, completion in
            for _ in container.persistentStoreDescriptions {
                completion(nil)
            }
        }
    ) {
        try slate.configure()
    }
}

private func cloudKitContainerIdentifier<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> String {
    let mirror = Mirror(reflecting: slate)
    for child in mirror.children where child.label == "storageMode" {
        switch child.value as? SlateStorageMode {
        case .cloudKitMirrored(let containerIdentifier), .cloudKitShared(let containerIdentifier):
            return containerIdentifier
        case .local:
            break
        case nil:
            break
        }
    }
    throw NSError(domain: "SlateSharingTests", code: -1)
}

private func slateStoreOwner<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> SlateStoreOwner<Schema> {
    let mirror = Mirror(reflecting: slate)
    for child in mirror.children where child.label == "owner" {
        if let owner = child.value as? SlateStoreOwner<Schema> {
            return owner
        }
    }
    throw NSError(domain: "SlateSharingTests", code: -2)
}

private func expectLoading<Schema: SlateSchema>(
    _ owner: SlateStoreOwner<Schema>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if case .loading = owner.loadState {
        return
    }
    Issue.record("Expected owner to be loading", sourceLocation: sourceLocation)
}

private func expectLoaded<Schema: SlateSchema>(
    _ owner: SlateStoreOwner<Schema>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if case .loaded = owner.loadState {
        return
    }
    Issue.record("Expected owner to be loaded", sourceLocation: sourceLocation)
}

private func expectFailed<Schema: SlateSchema>(
    _ owner: SlateStoreOwner<Schema>,
    expectedError: SlateError,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if case .failed(let error) = owner.loadState {
        #expect(error.slateError == expectedError, sourceLocation: sourceLocation)
        return
    }
    Issue.record("Expected owner to be failed", sourceLocation: sourceLocation)
}

private final class CapturedCloudKitLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedContainer: NSPersistentCloudKitContainer?
    private var capturedCompletion: ((Error?) -> Void)?

    func capture(
        container: NSPersistentCloudKitContainer,
        completion: @escaping (Error?) -> Void
    ) {
        lock.lock()
        precondition(capturedCompletion == nil, "CloudKit load was captured more than once")
        capturedContainer = container
        capturedCompletion = completion
        lock.unlock()
    }

    func requireCaptured() throws {
        lock.lock()
        let hasCompletion = capturedCompletion != nil
        lock.unlock()
        if !hasCompletion {
            throw NSError(
                domain: "SlateSharingTests",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "CloudKit load was not captured"]
            )
        }
    }

    func requireCapturedContainer() throws -> NSPersistentCloudKitContainer {
        lock.lock()
        defer { lock.unlock() }
        guard let capturedContainer else {
            throw NSError(
                domain: "SlateSharingTests",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "CloudKit container was not captured"]
            )
        }
        return capturedContainer
    }

    func completeSuccessfully() throws {
        try complete(error: nil)
    }

    func complete(error: Error?) throws {
        let completion: ((Error?) -> Void)?
        lock.lock()
        completion = capturedCompletion
        lock.unlock()

        guard let completion else {
            throw NSError(
                domain: "SlateSharingTests",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "CloudKit load completion was not captured"]
            )
        }
        completion(error)
    }
}

private func assertCloudKitStoreOptionsEnabled(
    _ description: NSPersistentStoreDescription,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        (description.options[NSPersistentHistoryTrackingKey] as? NSNumber)?.boolValue == true,
        sourceLocation: sourceLocation
    )
    #expect(
        (
            description.options[
                NSPersistentStoreRemoteChangeNotificationPostOptionKey
            ] as? NSNumber
        )?.boolValue == true,
        sourceLocation: sourceLocation
    )
}
