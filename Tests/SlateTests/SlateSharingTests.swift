import CloudKit
import CoreData
import Foundation
import ObjectiveC.runtime
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
    func participantLookupResultConstructsAndComparesByValue() throws {
        let participant = SlateParticipant(
            displayName: "Lookup Match",
            role: .privateUser,
            permission: .readOnly,
            acceptanceStatus: .accepted
        )
        let emailEntry = SlateParticipantLookupEntry(
            input: "reader@example.com",
            outcome: .found(participant)
        )
        let phoneEntry = SlateParticipantLookupEntry(
            input: "+15555550100",
            outcome: .failed(.notFound)
        )
        let result = SlateParticipantLookupResult(
            emailAddressResults: [emailEntry],
            phoneNumberResults: [phoneEntry]
        )

        #expect(emailEntry == SlateParticipantLookupEntry(
            input: "reader@example.com",
            outcome: .found(participant)
        ))
        #expect(phoneEntry == SlateParticipantLookupEntry(
            input: "+15555550100",
            outcome: .failed(.notFound)
        ))
        #expect(result == SlateParticipantLookupResult(
            emailAddressResults: [emailEntry],
            phoneNumberResults: [phoneEntry]
        ))
        #expect(result != SlateParticipantLookupResult(
            emailAddressResults: [phoneEntry],
            phoneNumberResults: [emailEntry]
        ))
    }

    @Test
    func participantLookupFailureCasesAreStable() {
        let failures: [SlateParticipantLookupFailure] = [
            .notFound,
            .invalidInput,
            .serviceUnavailable,
            .unknown,
        ]

        #expect(failures.count == 4)
        #expect(Set(failures.map(String.init(describing:))).count == failures.count)
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
    func sharingOwnerBoxExecutesSchemaSpecificOwnerOperations() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingOwnerBox")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let ownerBox = SlateSharingOwnerBox(owner: fixture.owner)

        try await ownerBox.waitUntilOwnerReady()
        let privateSlot = try await ownerBox.storeSlot(scope: .privateStore)
        let sharedSlot = try await ownerBox.storeSlot(scope: .sharedStore)
        #expect(privateSlot.scope == .privateStore)
        #expect(sharedSlot.scope == .sharedStore)
        let privateURL = try #require(privateSlot.store.url?.standardizedFileURL)
        let sharedURL = try #require(sharedSlot.store.url?.standardizedFileURL)
        #expect(sharedURL == SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: privateURL))

        let schemaIdentifier = try await ownerBox.withOwnerWriteGate {
            TestCloudKitRuntimeSchema.schemaIdentifier
        }
        #expect(schemaIdentifier == TestCloudKitRuntimeSchema.schemaIdentifier)

        let object = try await fixture.insertRecord(title: "Resolved object")
        let resolvedEntity = try await ownerBox.withResolvedObject(object) { resolved in
            #expect(resolved.id == object.slateID)
            #expect(resolved.managedObject.objectID == object.slateID)
            return resolved.entity
        }
        #expect(resolvedEntity == DatabaseTestCloudKitRuntimeRecord.slateEntityName)

        try await ownerBox.runRemoteChangeIngestion(scope: .privateStore)
        try await ownerBox.runRemoteChangeIngestion(scope: .sharedStore)
    }

    @Test
    func sharingStateResolvesObjectsOnlyFromPrivateStore() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingResolvePrivate")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let state = SlateSharingState(owner: fixture.owner)
        let object = try await fixture.insertRecord(title: "Private object")

        let resolved = try await state.resolveObject(object)

        #expect(resolved.id == object.slateID)
        #expect(resolved.managedObject.objectID == object.slateID)
        #expect(resolved.managedObject.objectID.persistentStore === resolved.privateStore)
        #expect(resolved.entity == DatabaseTestCloudKitRuntimeRecord.slateEntityName)
    }

    @Test
    func sharingStateThrowsUnavailableForTemporaryObjectID() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingResolveTemporary")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let state = SlateSharingState(owner: fixture.owner)
        let temporaryID = NSManagedObjectID()
        let object = TestCloudKitRuntimeRecord(
            slateID: temporaryID,
            title: "Temporary"
        )

        do {
            _ = try await state.resolveObject(object)
            Issue.record("Expected temporary sharing object ID to throw")
        } catch SlateError.sharingObjectUnavailable(let entity, let id) {
            #expect(entity == "TestCloudKitRuntimeRecord")
            if id !== temporaryID {
                Issue.record("Expected thrown ID to be the same temporary object ID")
            }
        } catch {
            Issue.record("Expected sharingObjectUnavailable, got \(error)")
        }
    }

    @Test
    func sharingStateThrowsUnavailableForDeletedObjectID() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingResolveDeleted")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let state = SlateSharingState(owner: fixture.owner)
        let object = try await fixture.insertRecord(title: "Deleted object")
        try await fixture.deleteRecord(object)

        await #expect(throws: SlateError.sharingObjectUnavailable(
            entity: "TestCloudKitRuntimeRecord",
            id: object.slateID
        )) {
            _ = try await state.resolveObject(object)
        }
    }

    @Test
    func sharingStateThrowsWrongStoreForSharedStoreObjectID() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingResolveWrongStore")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let state = SlateSharingState(owner: fixture.owner)
        let object = try await fixture.insertRecord(title: "Shared object", scope: .sharedStore)

        await #expect(throws: SlateError.sharingObjectWrongStore(
            entity: "TestCloudKitRuntimeRecord",
            id: object.slateID
        )) {
            _ = try await state.resolveObject(object)
        }
    }

    @Test
    func sharingStateThrowsStoreUnavailableWhenPrivateSlotIsMissing() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingMissingPrivateSlot")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(
            directory: directory,
            installedScopes: [.sharedStore]
        )
        let state = SlateSharingState(owner: fixture.owner)
        let object = TestCloudKitRuntimeRecord(title: "Missing private store")

        await #expect(throws: SlateError.sharingStoreUnavailable(scope: .privateStore)) {
            _ = try await state.resolveObject(object)
        }
    }

    @Test
    func mapsConstructedCloudKitShareToSlateSnapshot() {
        let rootRecord = CKRecord(recordType: "Root")
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Shared title" as CKRecordValue

        let snapshot = SlateShare(cloudKitShare: share)

        #expect(snapshot.url == share.url)
        #expect(snapshot.title == "Shared title")
        #expect(snapshot.owner == SlateParticipant(cloudKitParticipant: share.owner))
        #expect(snapshot.participants == share.participants.map(SlateParticipant.init(cloudKitParticipant:)))
        #expect(snapshot.currentUserPermission == .readWrite)
        #expect(snapshot.owner.role == .owner)
        #expect(snapshot.owner.permission == .readWrite)
        #expect(snapshot.owner.acceptanceStatus == .accepted)
    }

    @Test
    func shareForReturnsExistingSnapshotThroughFacade() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingShareFor")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Existing root")
        let existingShare = sharingTestShare(title: "Existing share")
        let probe = SharingAdapterProbe(
            fetchedShares: [existingShare],
            createdResults: []
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let snapshot = try await sharing.share(for: object)

        #expect(snapshot?.title == "Existing share")
        #expect(probe.events == [.fetch(object.slateID)])
        #expect(probe.adapterCallsInsideSlatePerform == [false])
    }

    @Test
    func shareCreatesWhenNoExistingShareIsPresent() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingCreate")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Created root")
        let createdShare = sharingTestShare()
        let probe = SharingAdapterProbe(
            fetchedShares: [nil],
            createdResults: [.success(SlateSharingPreparedShare(
                share: createdShare,
                container: nil
            ))]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let snapshot = try await sharing.share(object, title: "Created share")

        #expect(snapshot.title == "Created share")
        #expect(createdShare[CKShare.SystemFieldKey.title] as? String == "Created share")
        #expect(probe.events == [.fetch(object.slateID), .create(object.slateID)])
        #expect(probe.adapterCallsInsideSlatePerform == [false, false])
    }

    @Test
    func shareLeavesExistingShareTitleUnchanged() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingExistingTitle")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Existing title root")
        let existingShare = sharingTestShare(title: "Original title")
        let probe = SharingAdapterProbe(
            fetchedShares: [existingShare],
            createdResults: []
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let snapshot = try await sharing.share(object, title: "Replacement title")

        #expect(snapshot.title == "Original title")
        #expect(existingShare[CKShare.SystemFieldKey.title] as? String == "Original title")
        #expect(probe.events == [.fetch(object.slateID)])
        #expect(probe.adapterCallsInsideSlatePerform == [false])
    }

    @Test
    func shareRefetchesExistingShareAfterAlreadySharedCreateRace() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingDuplicateRace")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Race root")
        let racedShare = sharingTestShare(title: "Race winner")
        let probe = SharingAdapterProbe(
            fetchedShares: [nil, racedShare],
            createdResults: [.failure(alreadySharedError())]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let snapshot = try await sharing.share(object, title: "Losing title")

        #expect(snapshot.title == "Race winner")
        #expect(racedShare[CKShare.SystemFieldKey.title] as? String == "Race winner")
        #expect(probe.events == [
            .fetch(object.slateID),
            .create(object.slateID),
            .fetch(object.slateID),
        ])
        #expect(probe.adapterCallsInsideSlatePerform == [false, false, false])
    }

    @MainActor
    @Test
    func prepareShareReturnsLiveShareAndContainerWithoutPresentingUI() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingPrepare")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Prepared root")
        let createdShare = sharingTestShare()
        let container = probeContainer()
        let probe = SharingAdapterProbe(
            fetchedShares: [nil],
            createdResults: [.success(SlateSharingPreparedShare(
                share: createdShare,
                container: container
            ))]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let (share, returnedContainer) = try await sharing.prepareShare(for: object, title: "Prepared share")
        let sourceText = try slateSourceText()

        #expect(share === createdShare)
        #expect(returnedContainer === container)
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Prepared share")
        #expect(!sourceText.contains("UICloudSharingController"))
        #expect(!sourceText.contains("ShareLink"))
        #expect(probe.events == [.fetch(object.slateID), .create(object.slateID)])
        #expect(probe.adapterCallsInsideSlatePerform == [false, false])
    }

    @MainActor
    @Test
    func prepareShareLeavesExistingLiveShareTitleUnchanged() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingPrepareExisting")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Prepared existing root")
        let existingShare = sharingTestShare(title: "Existing prepared title")
        let container = probeContainer()
        let probe = SharingAdapterProbe(
            fetchedShares: [existingShare],
            createdResults: [],
            containerProvider: { container }
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let (share, returnedContainer) = try await sharing.prepareShare(for: object, title: "Replacement prepared title")

        #expect(share === existingShare)
        #expect(returnedContainer === container)
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Existing prepared title")
        #expect(probe.events == [.fetch(object.slateID)])
        #expect(probe.adapterCallsInsideSlatePerform == [false])
    }

    @Test
    func stopSharingReturnsSuccessfullyWhenNoShareExists() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingStopNoShare")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Unshared root")
        let ingestions = LockedTestCounter()
        fixture.owner.remoteChangeIngestor?.setIngestionHookForTesting {
            ingestions.increment()
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [nil],
            createdResults: []
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        try await sharing.stopSharing(object)

        #expect(probe.events == [.fetch(object.slateID)])
        #expect(probe.adapterCallsInsideSlatePerform == [false])
        #expect(ingestions.value == 0)
    }

    @Test
    func stopSharingDeletesShareWithRootRecordAndRunsPrivateIngestionAfterSuccess() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingStopSuccess")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Shared root")
        let rootRecord = CKRecord(
            recordType: "Root",
            recordID: CKRecord.ID(recordName: "root-stop-success")
        )
        let share = CKShare(rootRecord: rootRecord)
        let ingestions = LockedTestCounter()
        fixture.owner.remoteChangeIngestor?.setIngestionHookForTesting {
            ingestions.increment()
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [share],
            createdResults: [],
            rootRecordResults: [.success(rootRecord)],
            stopResults: [.success(())]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        try await sharing.stopSharing(object)

        #expect(probe.events == [
            .fetch(object.slateID),
            .fetchRootRecord(object.slateID, share.recordID),
            .stop(rootRecordID: rootRecord.recordID, shareRecordID: share.recordID),
        ])
        #expect(probe.adapterCallsInsideSlatePerform == [false, false, false])
        #expect(ingestions.value == 1)
    }

    @Test
    func stopSharingRootRecordFetchFailureDoesNotRunStopBatchOrIngestion() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingStopRootFailure")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Root failure")
        let share = sharingTestShare()
        let ingestions = LockedTestCounter()
        fixture.owner.remoteChangeIngestor?.setIngestionHookForTesting {
            ingestions.increment()
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [share],
            createdResults: [],
            rootRecordResults: [.failure(sharingProbeError("Root fetch failed"))],
            stopResults: []
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        do {
            try await sharing.stopSharing(object)
            Issue.record("Expected stopSharing to throw")
        } catch let error as SlateError {
            if case let .underlying(message) = error {
                #expect(message.contains("Root fetch failed"))
            } else {
                Issue.record("Expected underlying error, got \(error)")
            }
        }

        #expect(probe.events == [
            .fetch(object.slateID),
            .fetchRootRecord(object.slateID, share.recordID),
        ])
        #expect(ingestions.value == 0)
    }

    @Test
    func stopSharingBatchFailureDoesNotRunIngestion() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingStopBatchFailure")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Batch failure")
        let rootRecord = CKRecord(
            recordType: "Root",
            recordID: CKRecord.ID(recordName: "root-stop-failure")
        )
        let share = CKShare(rootRecord: rootRecord)
        let ingestions = LockedTestCounter()
        fixture.owner.remoteChangeIngestor?.setIngestionHookForTesting {
            ingestions.increment()
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [share],
            createdResults: [],
            rootRecordResults: [.success(rootRecord)],
            stopResults: [.failure(sharingProbeError("Stop batch failed"))]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        do {
            try await sharing.stopSharing(object)
            Issue.record("Expected stopSharing to throw")
        } catch let error as SlateError {
            if case let .underlying(message) = error {
                #expect(message.contains("Stop batch failed"))
            } else {
                Issue.record("Expected underlying error, got \(error)")
            }
        }

        #expect(probe.events == [
            .fetch(object.slateID),
            .fetchRootRecord(object.slateID, share.recordID),
            .stop(rootRecordID: rootRecord.recordID, shareRecordID: share.recordID),
        ])
        #expect(probe.adapterCallsInsideSlatePerform == [false, false, false])
        #expect(ingestions.value == 0)
    }

    @Test
    func acceptSharePassesMetadataToSharedStoreAndRunsSharedIngestionAfterSuccess() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingAcceptSuccess")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let metadata = sharingTestMetadata()
        let ingestedStoreURLs = LockedTestValues<URL?>()
        fixture.owner.remoteChangeIngestor?.setIngestionStoreURLHookForTesting { storeURL in
            ingestedStoreURLs.append(storeURL)
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [],
            createdResults: [],
            acceptResults: [.success(())]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        try await sharing.acceptShare(metadata)

        let sharedStoreURL = try fixture.storeURL(for: .sharedStore)
        #expect(probe.events == [
            .accept(
                metadataID: ObjectIdentifier(metadata),
                scope: .sharedStore,
                storeURL: sharedStoreURL
            ),
        ])
        #expect(probe.adapterCallsInsideSlatePerform == [false])
        #expect(ingestedStoreURLs.values == [sharedStoreURL])
    }

    @Test
    func acceptShareInvokesAdapterUnderOwnerWriteGate() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingAcceptWriteGate")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let metadata = sharingTestMetadata()
        let timeline = LockedTestValues<String>()
        let competingWrite = LockedTestTask()
        let adapter = SlateSharingCloudKitAdapter(
            fetchShare: { _, _ in
                throw sharingProbeError("Unexpected fetchShare adapter call")
            },
            createShare: { _, _ in
                throw sharingProbeError("Unexpected createShare adapter call")
            },
            fetchRootRecord: { _, _, _ in
                throw sharingProbeError("Unexpected fetchRootRecord adapter call")
            },
            stopSharing: { _, _, _ in
                throw sharingProbeError("Unexpected stopSharing adapter call")
            },
            acceptShare: { _, sharedSlot, ownerBox in
                #expect(sharedSlot.scope == .sharedStore)
                #expect(SlateCoreDataContextExecution.isInsideSlatePerform == false)
                timeline.append("accept-start")
                let queuedWrite = Task {
                    timeline.append("competing-attempt")
                    try await ownerBox.withOwnerWriteGate {
                        timeline.append("competing-write")
                    }
                }
                await competingWrite.set(queuedWrite)

                for _ in 0..<50 where !timeline.values.contains("competing-attempt") {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }

                #expect(timeline.values.contains("competing-attempt"))
                #expect(!timeline.values.contains("competing-write"))
                timeline.append("accept-end")
            },
            accountContainer: { _ in
                probeContainer()
            }
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: adapter
        ))

        try await sharing.acceptShare(metadata)
        try await competingWrite.value()

        #expect(timeline.values == [
            "accept-start",
            "competing-attempt",
            "accept-end",
            "competing-write",
        ])
    }

    @Test
    func acceptShareWaitsForOwnerReadinessBeforeResolvingStores() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingAcceptReadiness")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(
            directory: directory,
            loadState: .loading
        )
        let metadata = sharingTestMetadata()
        let probe = SharingAdapterProbe(
            fetchedShares: [],
            createdResults: [],
            acceptResults: [.success(())]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        let acceptTask = Task {
            try await sharing.acceptShare(metadata)
        }
        try await Task.sleep(nanoseconds: SlateOwnerReadiness.pollingIntervalNanoseconds * 2)
        #expect(probe.events.isEmpty)

        fixture.owner.markLoaded()
        try await acceptTask.value

        #expect(probe.events.count == 1)
        #expect(probe.adapterCallsInsideSlatePerform == [false])
    }

    @Test
    func acceptShareFailureDoesNotRunSharedIngestion() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingAcceptFailure")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let metadata = sharingTestMetadata()
        let ingestions = LockedTestCounter()
        fixture.owner.remoteChangeIngestor?.setIngestionHookForTesting {
            ingestions.increment()
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [],
            createdResults: [],
            acceptResults: [.failure(sharingProbeError("Accept failed"))]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        do {
            try await sharing.acceptShare(metadata)
            Issue.record("Expected acceptShare to throw")
        } catch let error as SlateError {
            if case let .underlying(message) = error {
                #expect(message.contains("Accept failed"))
            } else {
                Issue.record("Expected underlying error, got \(error)")
            }
        }

        #expect(probe.events == [
            .accept(
                metadataID: ObjectIdentifier(metadata),
                scope: .sharedStore,
                storeURL: try fixture.storeURL(for: .sharedStore)
            ),
        ])
        #expect(ingestions.value == 0)
    }

    @Test
    func acceptShareThrowsWhenSharedStoreSlotIsMissing() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingAcceptMissingSharedSlot")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(
            directory: directory,
            installedScopes: [.privateStore]
        )
        let metadata = sharingTestMetadata()
        let probe = SharingAdapterProbe(
            fetchedShares: [],
            createdResults: [],
            acceptResults: [.success(())]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        await #expect(throws: SlateError.sharingStoreUnavailable(scope: .sharedStore)) {
            try await sharing.acceptShare(metadata)
        }
        #expect(probe.events.isEmpty)
    }

    @Test
    func acceptShareUsesSharedIngestionAndStopSharingUsesPrivateIngestion() async throws {
        let directory = try temporaryDirectory(prefix: "SlateSharingLifecycleIngestionScopes")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = try SharingOwnerBoxFixture(directory: directory)
        let object = try await fixture.insertRecord(title: "Lifecycle root")
        let metadata = sharingTestMetadata()
        let rootRecord = CKRecord(
            recordType: "Root",
            recordID: CKRecord.ID(recordName: "root-lifecycle-ingestion")
        )
        let share = CKShare(rootRecord: rootRecord)
        let ingestedStoreURLs = LockedTestValues<URL?>()
        fixture.owner.remoteChangeIngestor?.setIngestionStoreURLHookForTesting { storeURL in
            ingestedStoreURLs.append(storeURL)
        }
        let probe = SharingAdapterProbe(
            fetchedShares: [share],
            createdResults: [],
            rootRecordResults: [.success(rootRecord)],
            stopResults: [.success(())],
            acceptResults: [.success(())]
        )
        let sharing = SlateSharing(state: SlateSharingState(
            owner: fixture.owner,
            sharingAdapter: probe.adapter()
        ))

        try await sharing.acceptShare(metadata)
        try await sharing.stopSharing(object)

        #expect(ingestedStoreURLs.values == [
            try fixture.storeURL(for: .sharedStore),
            try fixture.storeURL(for: .privateStore),
        ])
    }

    @Test
    func sprintEightStepFiveSourceSurfaceIsScoped() throws {
        let sourceText = try slateSourceText()
        let forbiddenTokens = [
            "initializeCloudKitSchema",
            "func persist(",
            "func persist<",
            "UICloudSharingController",
            "ShareLink",
        ]

        for token in forbiddenTokens {
            #expect(!sourceText.contains(token), "Unexpected Sprint 08 sharing surface found: \(token)")
        }

        #expect(!sourceText.contains("struct SlateSharing<"))
        #expect(sourceText.contains("public struct SlateSharing: Sendable"))
        #expect(sourceText.contains("public func share<V: SlateObject>("))
        #expect(sourceText.contains("public func share<V: SlateObject>(\n        for object: V"))
        #expect(sourceText.contains("public func stopSharing<V: SlateObject>("))
        #expect(sourceText.contains("public func acceptShare(_ metadata: CKShare.Metadata)"))
        #expect(sourceText.contains("public func prepareShare<V: SlateObject>("))
        #expect(sourceText.contains("title: String? = nil"))
        #expect(sourceText.contains(") async throws -> (CKShare, CKContainer)"))
        #expect(sourceText.contains("func lookupParticipants("))
        #expect(sourceText.contains(") async throws -> SlateParticipantLookupResult"))
        #expect(sourceText.contains("withCheckedThrowingContinuation"))
        #expect(sourceText.contains("withResolvedObject"))
        #expect(sourceText.contains("container.share([resolved.managedObject], to: nil)"))
        #expect(sourceText.contains("acceptShareInvitations("))
        #expect(sourceText.contains("CKModifyRecordsOperation("))
        #expect(!sourceText.contains("purgeObjectsAndRecordsInZone"))
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

private final class SharingOwnerBoxFixture: @unchecked Sendable {
    let owner: SlateStoreOwner<TestCloudKitRuntimeSchema>

    init(
        directory: URL,
        installedScopes: [SlateSharingStoreScope] = [.privateStore, .sharedStore],
        loadState: SlateStoreLoadState = .loaded
    ) throws {
        let privateURL = directory.appendingPathComponent("Private.sqlite")
        let sharedURL = SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: privateURL)

        let model = try TestCloudKitRuntimeSchema.makeManagedObjectModel()
        model.setEntities(model.entities, forConfigurationName: SlateCloudKitContainer.privateStoreConfigurationName)
        model.setEntities(model.entities, forConfigurationName: SlateCloudKitContainer.sharedStoreConfigurationName)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        for scope in installedScopes {
            switch scope {
            case .privateStore:
                try Self.addStore(
                    to: coordinator,
                    url: privateURL,
                    configuration: SlateCloudKitContainer.privateStoreConfigurationName
                )
            case .sharedStore:
                try Self.addStore(
                    to: coordinator,
                    url: sharedURL,
                    configuration: SlateCloudKitContainer.sharedStoreConfigurationName
                )
            }
        }

        let writerContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        writerContext.persistentStoreCoordinator = coordinator
        writerContext.undoManager = nil
        writerContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        var registry = SlateTableRegistry()
        TestCloudKitRuntimeSchema.registerTables(&registry)
        owner = SlateStoreOwner<TestCloudKitRuntimeSchema>(
            registry: registry,
            coordinator: coordinator,
            writerContext: writerContext,
            storageMode: .cloudKitShared(containerIdentifier: "iCloud.com.example.owner-box"),
            loadState: loadState
        )
        owner.installRemoteChangeIngestor(
            SlateRemoteChangeIngestor(
                owner: owner,
                storeURLs: [privateURL, sharedURL]
            )
        )
    }

    func insertRecord(
        title: String,
        scope: SlateSharingStoreScope = .privateStore
    ) async throws -> TestCloudKitRuntimeRecord {
        let writerContext = owner.writerContext
        let store = UncheckedSharingPersistentStore(try persistentStore(for: scope))
        return try await writerContext.slatePerform {
            let record = DatabaseTestCloudKitRuntimeRecord.create(in: writerContext)
            record.title = title
            writerContext.assign(record, to: store.value)
            try writerContext.obtainPermanentIDs(for: [record])
            try writerContext.save()
            return record.slateObject
        }
    }

    func storeURL(for scope: SlateSharingStoreScope) throws -> URL {
        try #require(persistentStore(for: scope).url?.standardizedFileURL)
    }

    func deleteRecord(_ object: TestCloudKitRuntimeRecord) async throws {
        let writerContext = owner.writerContext
        try await writerContext.slatePerform {
            let record = try writerContext.existingObject(with: object.slateID)
            writerContext.delete(record)
            try writerContext.save()
        }
    }

    private func persistentStore(for scope: SlateSharingStoreScope) throws -> NSPersistentStore {
        let configurationName: String
        switch scope {
        case .privateStore:
            configurationName = SlateCloudKitContainer.privateStoreConfigurationName
        case .sharedStore:
            configurationName = SlateCloudKitContainer.sharedStoreConfigurationName
        }

        guard let store = owner.coordinator.persistentStores.first(where: {
            $0.configurationName == configurationName
        }) else {
            throw SlateError.sharingStoreUnavailable(scope: scope)
        }
        return store
    }

    private static func addStore(
        to coordinator: NSPersistentStoreCoordinator,
        url: URL,
        configuration: String
    ) throws {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.configuration = configuration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        coordinator.addPersistentStore(with: description) { _, error in
            capturedError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let capturedError {
            throw capturedError
        }
    }
}

private struct UncheckedSharingPersistentStore: @unchecked Sendable {
    let value: NSPersistentStore

    init(_ value: NSPersistentStore) {
        self.value = value
    }
}

private enum SharingAdapterEvent: Equatable {
    case fetch(SlateID)
    case create(SlateID)
    case fetchRootRecord(SlateID, CKRecord.ID)
    case stop(rootRecordID: CKRecord.ID, shareRecordID: CKRecord.ID)
    case accept(metadataID: ObjectIdentifier, scope: SlateSharingStoreScope, storeURL: URL?)
}

private final class SharingAdapterProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var fetchedShares: [CKShare?]
    private var createdResults: [Result<SlateSharingPreparedShare, Error>]
    private var rootRecordResults: [Result<CKRecord, Error>]
    private var stopResults: [Result<Void, Error>]
    private var acceptResults: [Result<Void, Error>]
    private let containerProvider: @Sendable () -> CKContainer
    private var recordedEvents: [SharingAdapterEvent] = []
    private var recordedAdapterCallsInsideSlatePerform: [Bool] = []

    init(
        fetchedShares: [CKShare?],
        createdResults: [Result<SlateSharingPreparedShare, Error>],
        rootRecordResults: [Result<CKRecord, Error>] = [],
        stopResults: [Result<Void, Error>] = [],
        acceptResults: [Result<Void, Error>] = [],
        containerProvider: @escaping @Sendable () -> CKContainer = probeContainer
    ) {
        self.fetchedShares = fetchedShares
        self.createdResults = createdResults
        self.rootRecordResults = rootRecordResults
        self.stopResults = stopResults
        self.acceptResults = acceptResults
        self.containerProvider = containerProvider
    }

    var events: [SharingAdapterEvent] {
        lock.withLock {
            recordedEvents
        }
    }

    var adapterCallsInsideSlatePerform: [Bool] {
        lock.withLock {
            recordedAdapterCallsInsideSlatePerform
        }
    }

    func adapter() -> SlateSharingCloudKitAdapter {
        SlateSharingCloudKitAdapter(
            fetchShare: { [self] resolved, _ in
                try nextFetchedShare(for: resolved.id)
            },
            createShare: { [self] resolved, _ in
                try nextCreatedShare(for: resolved.id)
            },
            fetchRootRecord: { [self] rootObjectID, share, _ in
                try nextRootRecord(for: rootObjectID, share: share)
            },
            stopSharing: { [self] rootRecord, share, _ in
                try nextStop(rootRecord: rootRecord, share: share)
            },
            acceptShare: { [self] metadata, sharedSlot, _ in
                try nextAccept(metadata: metadata, sharedSlot: sharedSlot)
            },
            accountContainer: { [self] _ in
                containerProvider()
            }
        )
    }

    private func nextFetchedShare(for id: SlateID) throws -> CKShare? {
        try lock.withLock {
            recordedEvents.append(.fetch(id))
            recordedAdapterCallsInsideSlatePerform.append(SlateCoreDataContextExecution.isInsideSlatePerform)
            guard !fetchedShares.isEmpty else {
                throw NSError(
                    domain: "SlateSharingTests",
                    code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected fetchShare adapter call"]
                )
            }
            return fetchedShares.removeFirst()
        }
    }

    private func nextCreatedShare(for id: SlateID) throws -> SlateSharingPreparedShare {
        try lock.withLock {
            recordedEvents.append(.create(id))
            recordedAdapterCallsInsideSlatePerform.append(SlateCoreDataContextExecution.isInsideSlatePerform)
            guard !createdResults.isEmpty else {
                throw NSError(
                    domain: "SlateSharingTests",
                    code: -11,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected createShare adapter call"]
                )
            }
            return try createdResults.removeFirst().get()
        }
    }

    private func nextRootRecord(for id: SlateID, share: CKShare) throws -> CKRecord {
        try lock.withLock {
            recordedEvents.append(.fetchRootRecord(id, share.recordID))
            recordedAdapterCallsInsideSlatePerform.append(SlateCoreDataContextExecution.isInsideSlatePerform)
            guard !rootRecordResults.isEmpty else {
                throw NSError(
                    domain: "SlateSharingTests",
                    code: -12,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected fetchRootRecord adapter call"]
                )
            }
            return try rootRecordResults.removeFirst().get()
        }
    }

    private func nextStop(rootRecord: CKRecord, share: CKShare) throws {
        try lock.withLock {
            recordedEvents.append(.stop(
                rootRecordID: rootRecord.recordID,
                shareRecordID: share.recordID
            ))
            recordedAdapterCallsInsideSlatePerform.append(SlateCoreDataContextExecution.isInsideSlatePerform)
            guard !stopResults.isEmpty else {
                throw NSError(
                    domain: "SlateSharingTests",
                    code: -13,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected stopSharing adapter call"]
                )
            }
            try stopResults.removeFirst().get()
        }
    }

    private func nextAccept(metadata: CKShare.Metadata, sharedSlot: SlateSharingStoreSlot) throws {
        try lock.withLock {
            recordedEvents.append(.accept(
                metadataID: ObjectIdentifier(metadata),
                scope: sharedSlot.scope,
                storeURL: sharedSlot.store.url?.standardizedFileURL
            ))
            recordedAdapterCallsInsideSlatePerform.append(SlateCoreDataContextExecution.isInsideSlatePerform)
            guard !acceptResults.isEmpty else {
                throw NSError(
                    domain: "SlateSharingTests",
                    code: -14,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected acceptShare adapter call"]
                )
            }
            try acceptResults.removeFirst().get()
        }
    }
}

private func sharingTestShare(title: String? = nil) -> CKShare {
    let rootRecord = CKRecord(recordType: "Root")
    let share = CKShare(rootRecord: rootRecord)
    if let title {
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
    }
    return share
}

private func sharingTestMetadata() -> CKShare.Metadata {
    class_createInstance(CKShare.Metadata.self, 0) as! CKShare.Metadata
}

private func sharingProbeError(_ message: String) -> NSError {
    NSError(
        domain: "SlateSharingTests",
        code: -20,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}

private func probeContainer() -> CKContainer {
    // Constructing a real CKContainer requires iCloud entitlements. The fake adapter
    // only passes this object through for identity checks and never calls CK APIs.
    unsafeBitCast(ProbeContainerBox(), to: CKContainer.self)
}

private func alreadySharedError() -> NSError {
    NSError(
        domain: "CKErrorDomain",
        code: 30,
        userInfo: nil
    )
}

private final class ProbeContainerBox: NSObject {}

private final class LockedTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock {
            count
        }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}

private final class LockedTestValues<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Value] = []

    var values: [Value] {
        lock.withLock {
            recordedValues
        }
    }

    func append(_ value: Value) {
        lock.withLock {
            recordedValues.append(value)
        }
    }
}

private actor LockedTestTask {
    private var task: Task<Void, Error>?

    func set(_ task: Task<Void, Error>) {
        self.task = task
    }

    func value() async throws {
        try await task?.value
    }
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
