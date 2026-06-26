@preconcurrency import CoreData
import Foundation
import SlateSchema

public struct SlateSharing: Sendable {
    private let state: SlateSharingState

    init<Schema: SlateSchema>(owner: SlateStoreOwner<Schema>) {
        self.state = SlateSharingState(owner: owner)
    }
}

final class SlateSharingState: @unchecked Sendable {
    private let ownerReference: AnyObject
    private let cloudKitContainer: NSPersistentCloudKitContainer?

    /// The unchecked boundary is limited to retaining framework-backed owner
    /// state; sharing operations must route back through the owner's serialized
    /// access gates instead of freely using these references across actors.
    init<Schema: SlateSchema>(owner: SlateStoreOwner<Schema>) {
        self.ownerReference = owner
        self.cloudKitContainer = owner.cloudKitContainer
    }
}
