@preconcurrency import CloudKit
@preconcurrency import CoreData
import Foundation
import SlateSchema

public struct SlateSharing: Sendable {
    private let state: SlateSharingState

    init<Schema: SlateSchema>(owner: SlateStoreOwner<Schema>) {
        self.state = SlateSharingState(owner: owner)
    }

    init(state: SlateSharingState) {
        self.state = state
    }

    public func share<V: SlateObject>(
        _ object: V,
        title: String? = nil
    ) async throws -> SlateShare {
        let preparedShare = try await state.createOrFetchShare(
            for: object,
            title: title,
            requiresContainer: false
        )
        return state.snapshot(for: preparedShare.share)
    }

    public func share<V: SlateObject>(
        for object: V
    ) async throws -> SlateShare? {
        guard let share = try await state.fetchExistingShare(for: object) else {
            return nil
        }
        return state.snapshot(for: share)
    }

    @MainActor
    public func prepareShare<V: SlateObject>(
        for object: V,
        title: String? = nil
    ) async throws -> (CKShare, CKContainer) {
        let preparedShare = try await state.createOrFetchShare(
            for: object,
            title: title,
            requiresContainer: true
        )
        guard let container = preparedShare.container else {
            throw SlateError.coreData("Sharing operation completed without a CloudKit container")
        }
        return (preparedShare.share, container)
    }

    public func lookupParticipants(
        emailAddresses: [String],
        phoneNumbers: [String]
    ) async throws -> SlateParticipantLookupResult {
        _ = emailAddresses
        _ = phoneNumbers
        try await state.ownerBox.waitUntilOwnerReady()
        throw SlateError.underlying("Participant lookup is not implemented")
    }
}

final class SlateSharingState: @unchecked Sendable {
    let ownerBox: SlateSharingOwnerBox
    private let sharingAdapter: SlateSharingCloudKitAdapter

    init<Schema: SlateSchema>(
        owner: SlateStoreOwner<Schema>,
        sharingAdapter: SlateSharingCloudKitAdapter = .live
    ) {
        self.ownerBox = SlateSharingOwnerBox(owner: owner)
        self.sharingAdapter = sharingAdapter
    }

    init(
        ownerBox: SlateSharingOwnerBox,
        sharingAdapter: SlateSharingCloudKitAdapter = .live
    ) {
        self.ownerBox = ownerBox
        self.sharingAdapter = sharingAdapter
    }

    func resolveObject<V: SlateObject>(
        _ object: V
    ) async throws -> SlateSharingResolvedObject {
        try await ownerBox.withResolvedObject(object) { resolved in
            resolved
        }
    }

    func fetchExistingShare<V: SlateObject>(
        for object: V
    ) async throws -> CKShare? {
        try await ownerBox.withResolvedObject(object) { [sharingAdapter, ownerBox] resolved in
            try await sharingAdapter.fetchShare(resolved, ownerBox)
        }
    }

    func createOrFetchShare<V: SlateObject>(
        for object: V,
        title: String?,
        requiresContainer: Bool
    ) async throws -> SlateSharingPreparedShare {
        if let share = try await fetchExistingShare(for: object) {
            return SlateSharingPreparedShare(
                share: share,
                container: try containerIfNeeded(requiresContainer)
            )
        }

        let resolved = try await resolveObject(object)
        do {
            let preparedShare = try await sharingAdapter.createShare(resolved, ownerBox)
            apply(title: title, to: preparedShare.share)
            return preparedShare
        } catch {
            guard SlateSharingCloudKitAdapter.isAlreadySharedError(error),
                  let share = try await fetchExistingShare(for: object) else {
                throw error
            }
            return SlateSharingPreparedShare(
                share: share,
                container: try containerIfNeeded(requiresContainer)
            )
        }
    }

    func snapshot(for share: CKShare) -> SlateShare {
        SlateShare(cloudKitShare: share)
    }

    private func apply(title: String?, to share: CKShare) {
        guard let title else {
            return
        }
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
    }

    private func containerIfNeeded(_ requiresContainer: Bool) throws -> CKContainer? {
        guard requiresContainer else {
            return nil
        }
        return try sharingAdapter.accountContainer(ownerBox)
    }
}

struct SlateSharingStoreSlot: @unchecked Sendable {
    let scope: SlateSharingStoreScope
    let store: NSPersistentStore
}

struct SlateSharingResolvedObject: @unchecked Sendable {
    let entity: String
    let id: SlateID
    let managedObject: NSManagedObject
    let privateStore: NSPersistentStore
}

struct SlateUncheckedPersistentCloudKitContainer: @unchecked Sendable {
    let value: NSPersistentCloudKitContainer
}

struct SlateUncheckedCloudKitContainer: @unchecked Sendable {
    let value: CKContainer
}

struct SlateSharingPreparedShare: @unchecked Sendable {
    let share: CKShare
    let container: CKContainer?
}

struct SlateSharingCloudKitAdapter: Sendable {
    let fetchShare: @Sendable (SlateSharingResolvedObject, SlateSharingOwnerBox) async throws -> CKShare?
    let createShare: @Sendable (SlateSharingResolvedObject, SlateSharingOwnerBox) async throws -> SlateSharingPreparedShare
    let accountContainer: @Sendable (SlateSharingOwnerBox) throws -> CKContainer

    static let live = SlateSharingCloudKitAdapter(
        fetchShare: { resolved, ownerBox in
            let container = try ownerBox.persistentCloudKitContainer().value
            return try container.fetchShares(matching: [resolved.id])[resolved.id]
        },
        createShare: { resolved, ownerBox in
            let container = try ownerBox.persistentCloudKitContainer().value
            return try await SlateSharingAsyncCompletion.result { completion in
                container.share([resolved.managedObject], to: nil) { _, share, cloudKitContainer, error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    guard let share, let cloudKitContainer else {
                        completion(.failure(SlateError.coreData("Sharing operation completed without a share")))
                        return
                    }
                    completion(.success(SlateSharingPreparedShare(
                        share: share,
                        container: cloudKitContainer
                    )))
                }
            }
        },
        accountContainer: { ownerBox in
            try ownerBox.accountCloudKitContainer().value
        }
    )

    static func isAlreadySharedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "CKErrorDomain", nsError.code == 30 {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isAlreadySharedError(underlying)
        }

        if let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            return partialErrors.values.contains(where: isAlreadySharedError)
        }

        return false
    }
}

private struct SlateSharingAnySendable: @unchecked Sendable {
    let value: Any
}

final class SlateSharingOwnerBox: @unchecked Sendable {
    private let waitForOwnerReady: @Sendable () async throws -> Void
    private let runResolvedObjectPhase: @Sendable (
        NSManagedObjectID,
        String,
        @escaping @Sendable (SlateSharingResolvedObject) async throws -> SlateSharingAnySendable
    ) async throws -> SlateSharingAnySendable
    private let resolveStoreSlot: @Sendable (SlateSharingStoreScope) async throws -> SlateSharingStoreSlot
    private let runWriteGate: @Sendable (
        @escaping @Sendable () async throws -> SlateSharingAnySendable
    ) async throws -> SlateSharingAnySendable
    private let persistentCloudKitContainerProvider: @Sendable () throws -> SlateUncheckedPersistentCloudKitContainer
    private let accountCloudKitContainerProvider: @Sendable () throws -> SlateUncheckedCloudKitContainer
    private let remoteChangeIngestionRunner: @Sendable (SlateSharingStoreScope) async throws -> Void

    init<Schema: SlateSchema>(owner: SlateStoreOwner<Schema>) {
        waitForOwnerReady = {
            try await SlateSharingOwnerBox.waitUntilLoaded(owner)
        }
        runResolvedObjectPhase = { objectID, entity, operation in
            try await SlateSharingOwnerBox.withResolvedObjectPhase(
                objectID: objectID,
                entity: entity,
                owner: owner,
                operation
            )
        }
        resolveStoreSlot = { scope in
            try await SlateSharingOwnerBox.storeSlot(scope: scope, owner: owner)
        }
        runWriteGate = { operation in
            try await owner.accessGate.write {
                try await operation()
            }
        }
        persistentCloudKitContainerProvider = {
            guard let cloudKitContainer = owner.cloudKitContainer else {
                throw SlateError.cloudKitUnavailable(mode: owner.storageMode)
            }
            return SlateUncheckedPersistentCloudKitContainer(value: cloudKitContainer)
        }
        accountCloudKitContainerProvider = {
            guard let accountContainer = owner.cloudKitAccountContainer else {
                throw SlateError.cloudKitUnavailable(mode: owner.storageMode)
            }
            return SlateUncheckedCloudKitContainer(value: accountContainer)
        }
        remoteChangeIngestionRunner = { scope in
            let slot = try await SlateSharingOwnerBox.storeSlot(scope: scope, owner: owner)
            guard let storeURL = slot.store.url else {
                throw SlateError.sharingStoreUnavailable(scope: scope)
            }
            guard let ingestor = owner.remoteChangeIngestor else {
                throw SlateError.coreData("Remote-change ingestor is unavailable for \(scope)")
            }
            try await ingestor.ingestRemoteChange(forStoreURL: storeURL)
        }
    }

    func waitUntilOwnerReady() async throws {
        try await waitForOwnerReady()
    }

    func withResolvedObject<V: SlateObject, T: Sendable>(
        _ object: V,
        _ operation: @Sendable @escaping (SlateSharingResolvedObject) async throws -> T
    ) async throws -> T {
        let boxed = try await runResolvedObjectPhase(object.slateID, String(describing: V.self)) { resolved in
            SlateSharingAnySendable(value: try await operation(resolved))
        }
        guard let value = boxed.value as? T else {
            throw SlateError.coreData("Sharing resolved-object phase returned unexpected result")
        }
        return value
    }

    func storeSlot(scope: SlateSharingStoreScope) async throws -> SlateSharingStoreSlot {
        try await resolveStoreSlot(scope)
    }

    func withOwnerWriteGate<T: Sendable>(
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let boxed = try await runWriteGate {
            SlateSharingAnySendable(value: try await operation())
        }
        guard let value = boxed.value as? T else {
            throw SlateError.coreData("Sharing owner write gate returned unexpected result")
        }
        return value
    }

    func persistentCloudKitContainer() throws -> SlateUncheckedPersistentCloudKitContainer {
        try persistentCloudKitContainerProvider()
    }

    func accountCloudKitContainer() throws -> SlateUncheckedCloudKitContainer {
        try accountCloudKitContainerProvider()
    }

    func runRemoteChangeIngestion(scope: SlateSharingStoreScope) async throws {
        try await remoteChangeIngestionRunner(scope)
    }

    private static func waitUntilLoaded<Schema: SlateSchema>(
        _ owner: SlateStoreOwner<Schema>
    ) async throws {
        while true {
            if try await SlateOwnerReadiness.isLoadedOrWait(owner.loadState) {
                return
            }
        }
    }

    private static func withResolvedObjectPhase<Schema: SlateSchema>(
        objectID: NSManagedObjectID,
        entity: String,
        owner: SlateStoreOwner<Schema>,
        _ operation: @escaping @Sendable (SlateSharingResolvedObject) async throws -> SlateSharingAnySendable
    ) async throws -> SlateSharingAnySendable {
        try await waitUntilLoaded(owner)
        let privateSlot = try await storeSlot(scope: .privateStore, owner: owner)
        return try await owner.accessGate.write {
            let resolved = try await owner.writerContext.slatePerform {
                guard !objectID.isMember(of: NSManagedObjectID.self) else {
                    throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                }
                guard !objectID.isTemporaryID else {
                    throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                }

                do {
                    let managedObject = try owner.writerContext.existingObject(with: objectID)
                    guard !managedObject.isDeleted else {
                        throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                    }
                    guard !managedObject.objectID.isTemporaryID else {
                        throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                    }
                    guard managedObject.objectID.persistentStore === privateSlot.store else {
                        throw SlateError.sharingObjectWrongStore(entity: entity, id: objectID)
                    }
                    return SlateSharingResolvedObject(
                        entity: managedObject.entity.name ?? entity,
                        id: objectID,
                        managedObject: managedObject,
                        privateStore: privateSlot.store
                    )
                } catch let error as SlateError {
                    throw error
                } catch {
                    throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                }
            }
            return try await operation(resolved)
        }
    }

    private static func storeSlot<Schema: SlateSchema>(
        scope: SlateSharingStoreScope,
        owner: SlateStoreOwner<Schema>
    ) async throws -> SlateSharingStoreSlot {
        try await waitUntilLoaded(owner)
        let configurationName: String
        switch scope {
        case .privateStore:
            configurationName = SlateCloudKitContainer.privateStoreConfigurationName
        case .sharedStore:
            configurationName = SlateCloudKitContainer.sharedStoreConfigurationName
        }

        let store = owner.coordinator.persistentStores.first(where: {
            $0.configurationName == configurationName
        }) ?? storeSlotByURL(scope: scope, stores: owner.coordinator.persistentStores)

        guard let store else {
            throw SlateError.sharingStoreUnavailable(scope: scope)
        }
        return SlateSharingStoreSlot(scope: scope, store: store)
    }

    private static func storeSlotByURL(
        scope: SlateSharingStoreScope,
        stores: [NSPersistentStore]
    ) -> NSPersistentStore? {
        switch scope {
        case .privateStore:
            return stores.first { candidate in
                guard let candidateURL = candidate.url?.standardizedFileURL else {
                    return false
                }
                let expectedSharedURL = SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: candidateURL)
                return stores.contains { store in
                    store.url?.standardizedFileURL == expectedSharedURL
                }
            }
        case .sharedStore:
            return stores.first { candidate in
                guard let candidateURL = candidate.url?.standardizedFileURL else {
                    return false
                }
                return stores.contains { store in
                    guard let privateURL = store.url?.standardizedFileURL else {
                        return false
                    }
                    return SlateCloudKitContainer.sharedStoreURL(forPrivateStoreURL: privateURL) == candidateURL
                }
            }
        }
    }
}

extension SlateShare {
    init(cloudKitShare share: CKShare) {
        let currentUserPermission = SlateSharePermission(
            cloudKitPermission: share.currentUserParticipant?.permission ?? share.owner.permission
        )
        self.init(
            url: share.url,
            title: share[CKShare.SystemFieldKey.title] as? String,
            owner: SlateParticipant(cloudKitParticipant: share.owner),
            participants: share.participants.map(SlateParticipant.init(cloudKitParticipant:)),
            currentUserPermission: currentUserPermission
        )
    }
}

extension SlateParticipant {
    init(cloudKitParticipant participant: CKShare.Participant) {
        self.init(
            displayName: participant.slateDisplayName,
            role: SlateShareRole(cloudKitRole: participant.role),
            permission: SlateSharePermission(cloudKitPermission: participant.permission),
            acceptanceStatus: SlateShareAcceptance(
                cloudKitAcceptanceStatus: participant.acceptanceStatus
            )
        )
    }
}

private extension CKShare.Participant {
    var slateDisplayName: String? {
        guard let nameComponents = userIdentity.nameComponents else {
            return nil
        }

        let displayName = PersonNameComponentsFormatter.localizedString(
            from: nameComponents,
            style: .default
        )
        return displayName.isEmpty ? nil : displayName
    }
}

enum SlateSharingAsyncCompletion {
    static func result<T: Sendable>(
        _ start: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            start { result in
                continuation.resume(with: result)
            }
        }
    }

    static func value<T: Sendable>(
        missingResultMessage: String = "Sharing operation completed without a result",
        _ start: (@escaping @Sendable (T?, Error?) -> Void) -> Void
    ) async throws -> T {
        try await result { completion in
            start { value, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let value else {
                    completion(.failure(SlateError.coreData(missingResultMessage)))
                    return
                }
                completion(.success(value))
            }
        }
    }

    static func void(
        _ start: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        let _: Void = try await result { completion in
            start { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                completion(.success(()))
            }
        }
    }
}
