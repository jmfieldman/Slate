@preconcurrency import CloudKit
@preconcurrency import CoreData
import Foundation
import SlateSchema

public struct SlateSharing: Sendable {
    private let state: SlateSharingState

    init<Schema: SlateSchema>(owner: SlateStoreOwner<Schema>) {
        self.state = SlateSharingState(owner: owner)
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

    init<Schema: SlateSchema>(owner: SlateStoreOwner<Schema>) {
        self.ownerBox = SlateSharingOwnerBox(owner: owner)
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
}

struct SlateUncheckedPersistentCloudKitContainer: @unchecked Sendable {
    let value: NSPersistentCloudKitContainer
}

struct SlateUncheckedCloudKitContainer: @unchecked Sendable {
    let value: CKContainer
}

private struct SlateSharingAnySendable: @unchecked Sendable {
    let value: Any
}

final class SlateSharingOwnerBox: @unchecked Sendable {
    private let waitForOwnerReady: @Sendable () async throws -> Void
    private let resolveObjectInWriterContext: @Sendable (NSManagedObjectID, String) async throws -> SlateSharingResolvedObject
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
        resolveObjectInWriterContext = { objectID, entity in
            try await SlateSharingOwnerBox.resolveObject(
                objectID: objectID,
                entity: entity,
                owner: owner
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

    func resolveObject<V: SlateObject>(_ object: V) async throws -> SlateSharingResolvedObject {
        try await resolveObjectInWriterContext(object.slateID, String(describing: V.self))
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

    private static func resolveObject<Schema: SlateSchema>(
        objectID: NSManagedObjectID,
        entity: String,
        owner: SlateStoreOwner<Schema>
    ) async throws -> SlateSharingResolvedObject {
        try await waitUntilLoaded(owner)
        return try await owner.accessGate.write {
            try await owner.writerContext.slatePerform {
                do {
                    let managedObject = try owner.writerContext.existingObject(with: objectID)
                    guard !managedObject.isDeleted else {
                        throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                    }
                    return SlateSharingResolvedObject(
                        entity: managedObject.entity.name ?? entity,
                        id: objectID,
                        managedObject: managedObject
                    )
                } catch let error as SlateError {
                    throw error
                } catch {
                    throw SlateError.sharingObjectUnavailable(entity: entity, id: objectID)
                }
            }
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
