@preconcurrency import CoreData
import Foundation
import Observation
import SlateSchema

public enum SlateStreamState: Sendable, Equatable {
    case loading
    case ready
    case failed
    case cancelled
}

@globalActor
public actor SlateStreamActor {
    public static let shared = SlateStreamActor()
}

@MainActor
@Observable
public final class SlateStream<Value> where Value: SlateObject {
    public private(set) var values: [Value] = []
    public var value: Value? { values.first }
    public private(set) var state: SlateStreamState = .loading
    public private(set) var error: Error?

    @ObservationIgnored
    private let core: SlateStreamCore<Value>

    @ObservationIgnored
    private var asyncContinuations: [UUID: AsyncThrowingStream<[Value], Error>.Continuation] = [:]

    init(core: SlateStreamCore<Value>) {
        self.core = core
        core.bindMain(self)
    }

    public func cancel() {
        guard state != .cancelled else { return }
        core.cancel()
        state = .cancelled
        finishAsyncStreams()
    }

    public var valuesAsync: AsyncThrowingStream<[Value], Error> {
        let id = UUID()
        let initialValues = values
        let initialState = state
        let initialError = error
        return AsyncThrowingStream<[Value], Error> { continuation in
            asyncContinuations[id] = continuation
            continuation.yield(initialValues)
            switch initialState {
            case .ready, .loading:
                break
            case .failed:
                continuation.finish(throwing: initialError ?? SlateError.coreData("Stream failed"))
                asyncContinuations.removeValue(forKey: id)
            case .cancelled:
                continuation.finish()
                asyncContinuations.removeValue(forKey: id)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.asyncContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    public var valueAsync: AsyncThrowingStream<Value?, Error> {
        let upstream = valuesAsync
        return AsyncThrowingStream<Value?, Error> { continuation in
            let task = Task {
                do {
                    for try await values in upstream {
                        continuation.yield(values.first)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    fileprivate func updateValues(_ newValues: [Value]) {
        guard state != .cancelled else { return }
        values = newValues
        if state != .ready {
            state = .ready
        }
        for continuation in asyncContinuations.values {
            continuation.yield(newValues)
        }
    }

    fileprivate func updateError(_ newError: Error) {
        guard state != .cancelled else { return }
        error = newError
        state = .failed
        for continuation in asyncContinuations.values {
            continuation.finish(throwing: newError)
        }
        asyncContinuations.removeAll()
    }

    fileprivate func finishAsyncStreams() {
        for continuation in asyncContinuations.values {
            continuation.finish()
        }
        asyncContinuations.removeAll()
    }

    deinit {
        core.cancel()
    }
}

@SlateStreamActor
@Observable
public final class SlateBackgroundStream<Value> where Value: SlateObject {
    public private(set) var values: [Value] = []
    public var value: Value? { values.first }
    public private(set) var state: SlateStreamState = .loading
    public private(set) var error: Error?

    @ObservationIgnored
    private let core: SlateStreamCore<Value>

    @ObservationIgnored
    private var asyncContinuations: [UUID: AsyncThrowingStream<[Value], Error>.Continuation] = [:]

    nonisolated init(core: SlateStreamCore<Value>) {
        self.core = core
        core.bindBackground(self)
    }

    public func cancel() {
        guard state != .cancelled else { return }
        core.cancel()
        state = .cancelled
        finishAsyncStreams()
    }

    public var valuesAsync: AsyncThrowingStream<[Value], Error> {
        let id = UUID()
        let initialValues = values
        let initialState = state
        let initialError = error
        return AsyncThrowingStream<[Value], Error> { continuation in
            asyncContinuations[id] = continuation
            continuation.yield(initialValues)
            switch initialState {
            case .ready, .loading:
                break
            case .failed:
                continuation.finish(throwing: initialError ?? SlateError.coreData("Stream failed"))
                asyncContinuations.removeValue(forKey: id)
            case .cancelled:
                continuation.finish()
                asyncContinuations.removeValue(forKey: id)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @SlateStreamActor [weak self] in
                    self?.asyncContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    public var valueAsync: AsyncThrowingStream<Value?, Error> {
        let upstream = valuesAsync
        return AsyncThrowingStream<Value?, Error> { continuation in
            let task = Task {
                do {
                    for try await values in upstream {
                        continuation.yield(values.first)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    fileprivate func updateValues(_ newValues: [Value]) {
        guard state != .cancelled else { return }
        values = newValues
        if state != .ready {
            state = .ready
        }
        for continuation in asyncContinuations.values {
            continuation.yield(newValues)
        }
    }

    fileprivate func updateError(_ newError: Error) {
        guard state != .cancelled else { return }
        error = newError
        state = .failed
        for continuation in asyncContinuations.values {
            continuation.finish(throwing: newError)
        }
        asyncContinuations.removeAll()
    }

    fileprivate func finishAsyncStreams() {
        for continuation in asyncContinuations.values {
            continuation.finish()
        }
        asyncContinuations.removeAll()
    }

    deinit {
        core.cancel()
    }
}

private struct UncheckedNotification: @unchecked Sendable {
    let value: Notification
}

final class SlateStreamCore<Value: SlateObject>: NSObject, NSFetchedResultsControllerDelegate, @unchecked Sendable {
    typealias BatchDeleteHandler = @Sendable ([NSManagedObjectID]) -> Void

    private let context: NSManagedObjectContext
    private let frc: NSFetchedResultsController<NSFetchRequestResult>
    private let convert: @Sendable (NSManagedObject) throws -> Value
    private let writerContext: NSManagedObjectContext
    private let unregisterBatchDeleteSink: @Sendable (UUID) -> Void

    private weak var mainStream: SlateStream<Value>?
    private weak var backgroundStream: SlateBackgroundStream<Value>?

    private let stateLock = NSLock()
    private var didSaveObserver: NSObjectProtocol?
    private var batchDeleteSinkID: UUID?
    private var cancelled = false
    private var initialFetchScheduled = false

    init(
        context: NSManagedObjectContext,
        frc: NSFetchedResultsController<NSFetchRequestResult>,
        convert: @escaping @Sendable (NSManagedObject) throws -> Value,
        writerContext: NSManagedObjectContext,
        registerBatchDeleteSink: (@Sendable (@escaping BatchDeleteHandler) -> UUID)? = nil,
        unregisterBatchDeleteSink: @escaping @Sendable (UUID) -> Void = { _ in }
    ) {
        self.context = context
        self.frc = frc
        self.convert = convert
        self.writerContext = writerContext
        self.unregisterBatchDeleteSink = unregisterBatchDeleteSink
        super.init()
        attachWriterMergeObserver()
        if let registerBatchDeleteSink {
            attachBatchDeleteSink(register: registerBatchDeleteSink)
        }
    }

    func bindMain(_ stream: SlateStream<Value>) {
        stateLock.lock()
        mainStream = stream
        stateLock.unlock()
        scheduleInitialFetchIfNeeded()
    }

    func bindBackground(_ stream: SlateBackgroundStream<Value>) {
        stateLock.lock()
        backgroundStream = stream
        stateLock.unlock()
        scheduleInitialFetchIfNeeded()
    }

    private func scheduleInitialFetchIfNeeded() {
        stateLock.lock()
        let shouldSchedule = !initialFetchScheduled && !cancelled
        if shouldSchedule {
            initialFetchScheduled = true
        }
        stateLock.unlock()
        guard shouldSchedule else { return }
        context.perform { [weak self] in
            self?.performInitialFetch()
        }
    }

    private func performInitialFetch() {
        do {
            try frc.performFetch()
            let objects = (frc.fetchedObjects as? [NSManagedObject]) ?? []
            let values = try objects.map(convert)
            publishValues(values)
        } catch {
            publishError(error)
        }
    }

    private func attachBatchDeleteSink(
        register: @Sendable (@escaping BatchDeleteHandler) -> UUID
    ) {
        let id = register { [weak self] deletedIDs in
            guard let self else { return }
            self.context.perform { [weak self] in
                guard let self else { return }
                let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedIDs]
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: changes,
                    into: [self.context]
                )
                do {
                    try self.frc.performFetch()
                    let objects = (self.frc.fetchedObjects as? [NSManagedObject]) ?? []
                    let values = try objects.map(self.convert)
                    self.publishValues(values)
                } catch {
                    self.publishError(error)
                }
            }
        }
        stateLock.lock()
        batchDeleteSinkID = id
        stateLock.unlock()
    }

    private func attachWriterMergeObserver() {
        let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: writerContext,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let box = UncheckedNotification(value: notification)
            self.context.perform { [weak self] in
                guard let self else { return }
                self.context.mergeChanges(fromContextDidSave: box.value)
                do {
                    try self.frc.performFetch()
                    let objects = (self.frc.fetchedObjects as? [NSManagedObject]) ?? []
                    let values = try objects.map(self.convert)
                    self.publishValues(values)
                } catch {
                    self.publishError(error)
                }
            }
        }
        stateLock.lock()
        didSaveObserver = observer
        stateLock.unlock()
    }

    func cancel() {
        stateLock.lock()
        if cancelled {
            stateLock.unlock()
            return
        }
        cancelled = true
        let observer = didSaveObserver
        let sinkID = batchDeleteSinkID
        didSaveObserver = nil
        batchDeleteSinkID = nil
        stateLock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let sinkID {
            unregisterBatchDeleteSink(sinkID)
        }
        context.perform { [frc] in
            frc.delegate = nil
        }
    }

    private func publishValues(_ values: [Value]) {
        stateLock.lock()
        let isCancelled = cancelled
        let main = mainStream
        let background = backgroundStream
        stateLock.unlock()
        guard !isCancelled else { return }
        if main != nil {
            Task { @MainActor [weak main] in
                main?.updateValues(values)
            }
        }
        if background != nil {
            Task { @SlateStreamActor [weak background] in
                background?.updateValues(values)
            }
        }
    }

    private func publishError(_ error: Error) {
        stateLock.lock()
        let isCancelled = cancelled
        let main = mainStream
        let background = backgroundStream
        stateLock.unlock()
        guard !isCancelled else { return }
        if main != nil {
            Task { @MainActor [weak main] in
                main?.updateError(error)
            }
        }
        if background != nil {
            Task { @SlateStreamActor [weak background] in
                background?.updateError(error)
            }
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let objects = (controller.fetchedObjects as? [NSManagedObject]) ?? []
        do {
            let values = try objects.map(convert)
            publishValues(values)
        } catch {
            publishError(error)
        }
    }

    deinit {
        if let observer = didSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let id = batchDeleteSinkID {
            unregisterBatchDeleteSink(id)
        }
    }
}
