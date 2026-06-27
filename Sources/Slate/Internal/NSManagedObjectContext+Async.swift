@preconcurrency import CoreData
import Foundation

enum SlateCoreDataContextExecution {
    @TaskLocal static var isInsideSlatePerform = false
}

extension NSManagedObjectContext {
    func slatePerform<T>(_ block: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            perform {
                do {
                    let value = try SlateCoreDataContextExecution.$isInsideSlatePerform.withValue(true) {
                        try block()
                    }
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
