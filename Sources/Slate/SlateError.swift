@preconcurrency import CoreData
import Foundation

public enum SlateError: Error, Sendable, Equatable {
    case notConfigured
    case alreadyConfigured
    case closed
    case nestedTransaction
    case missingTable(String)
    case missingEntity(String)
    case incompatibleStore(URL?)
    case wipeFailed(URL, String)
    case invalidStoredValue(entity: String, property: String, valueDescription: String)
    case invalidKeyPath(String)
    case emptyDeleteMissingSet
    /// Thrown by `upsert`/`upsertMany` when the supplied key path does not
    /// correspond to a declared single-attribute uniqueness constraint on
    /// the entity. Without uniqueness, an upsert key could match multiple
    /// rows and the operation would have ambiguous semantics.
    case upsertKeyNotUnique(entity: String, attribute: String)
    case coreData(String)
    case underlying(String)
}

public enum SlateStoreKind: Sendable, Equatable {
    case strict
    case cacheStore
}

enum SlateTransactionKind: Sendable {
    case query
    case mutation
    case streamConversion
}

struct SlateTransactionScope: Sendable {
    let ownerID: UUID
    let scopeID: UUID
    let kind: SlateTransactionKind
}

enum SlateTransactionScopeKey {
    @TaskLocal static var current: SlateTransactionScope?
}

extension Error {
    var slateError: SlateError {
        if let slateError = self as? SlateError {
            return slateError
        }
        return .underlying(String(describing: self))
    }
}
