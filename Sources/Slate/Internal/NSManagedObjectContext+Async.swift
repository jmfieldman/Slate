@preconcurrency import CoreData
import Foundation

extension NSManagedObjectContext {
    func slatePerform<T>(_ block: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            perform {
                do {
                    continuation.resume(returning: try block())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
