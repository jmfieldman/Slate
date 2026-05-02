@preconcurrency import CoreData
import Foundation
import SlateSchema

/// Lock-protected store of converted immutable Slate objects keyed by Core
/// Data permanent object IDs.
///
/// The cache is intended to give stream emissions and repeated reads a way to
/// avoid reconverting unchanged managed objects. Mutations apply cache
/// updates pre-save so FRC/stream conversions during save propagation can
/// reuse the hydrated values; on save failure the cache is restored from
/// the captured undo snapshot.
final class SlateObjectCache: @unchecked Sendable {
    /// Snapshot of a single cache entry, used as undo state for a mutation.
    enum UndoEntry: Sendable {
        case absent
        case present(any SlateObject)
    }

    private var entries: [NSManagedObjectID: any SlateObject] = [:]
    private let lock = NSLock()

    func get(_ id: NSManagedObjectID) -> (any SlateObject)? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]
    }

    func set(_ id: NSManagedObjectID, _ value: any SlateObject) {
        lock.lock()
        defer { lock.unlock() }
        entries[id] = value
    }

    func remove(_ ids: some Sequence<NSManagedObjectID>) {
        lock.lock()
        defer { lock.unlock() }
        for id in ids {
            entries.removeValue(forKey: id)
        }
    }

    func contains(_ id: NSManagedObjectID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[id] != nil
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Capture the current cache state for the given IDs as an undo set.
    func snapshot(_ ids: some Sequence<NSManagedObjectID>) -> [NSManagedObjectID: UndoEntry] {
        lock.lock()
        defer { lock.unlock() }
        var result: [NSManagedObjectID: UndoEntry] = [:]
        for id in ids {
            if let existing = entries[id] {
                result[id] = .present(existing)
            } else {
                result[id] = .absent
            }
        }
        return result
    }

    /// Apply a batch of cache updates: set values for `setting`, remove the
    /// IDs in `removing`. Atomic under the cache lock.
    func apply(setting: [NSManagedObjectID: any SlateObject], removing: some Sequence<NSManagedObjectID>) {
        lock.lock()
        defer { lock.unlock() }
        for (id, value) in setting {
            entries[id] = value
        }
        for id in removing {
            entries.removeValue(forKey: id)
        }
    }

    /// Restore cache entries from a previously captured undo snapshot.
    func restore(_ undo: [NSManagedObjectID: UndoEntry]) {
        lock.lock()
        defer { lock.unlock() }
        for (id, entry) in undo {
            switch entry {
            case .absent:
                entries.removeValue(forKey: id)
            case .present(let value):
                entries[id] = value
            }
        }
    }
}
