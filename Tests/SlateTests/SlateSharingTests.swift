import CloudKit
import CoreData
import Foundation
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
