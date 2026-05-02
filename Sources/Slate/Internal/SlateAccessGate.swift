import Foundation

/// FIFO reader/writer access gate with write priority.
///
/// Reads run concurrently. Writes are exclusive. A new read waits if any
/// write is queued ahead of it so writers cannot be starved.
actor SlateAccessGate {
    private enum Waiter {
        case read(id: UUID, continuation: CheckedContinuation<Void, Error>)
        case write(id: UUID, continuation: CheckedContinuation<Void, Error>)

        var id: UUID {
            switch self {
            case let .read(id, _), let .write(id, _): id
            }
        }
    }

    private var readerCount = 0
    private var writerActive = false
    private var queue: [Waiter] = []

    func read<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await acquireRead()
        do {
            let value = try await block()
            releaseRead()
            return value
        } catch {
            releaseRead()
            throw error
        }
    }

    func write<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await acquireWrite()
        do {
            let value = try await block()
            releaseWrite()
            return value
        } catch {
            releaseWrite()
            throw error
        }
    }

    private func acquireRead() async throws {
        try Task.checkCancellation()
        if !writerActive && queue.isEmpty {
            readerCount += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.append(.read(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func acquireWrite() async throws {
        try Task.checkCancellation()
        if !writerActive && readerCount == 0 && queue.isEmpty {
            writerActive = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.append(.write(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func releaseRead() {
        readerCount -= 1
        drainQueue()
    }

    private func releaseWrite() {
        writerActive = false
        drainQueue()
    }

    private func drainQueue() {
        while let head = queue.first {
            switch head {
            case let .read(_, continuation):
                if writerActive {
                    return
                }
                queue.removeFirst()
                readerCount += 1
                continuation.resume()
            case let .write(_, continuation):
                if writerActive || readerCount > 0 {
                    return
                }
                queue.removeFirst()
                writerActive = true
                continuation.resume()
                return
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = queue.remove(at: index)
        switch waiter {
        case let .read(_, continuation), let .write(_, continuation):
            continuation.resume(throwing: CancellationError())
        }
        drainQueue()
    }
}
