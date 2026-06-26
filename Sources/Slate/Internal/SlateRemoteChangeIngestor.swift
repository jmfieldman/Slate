@preconcurrency import CoreData
import Foundation
import SlateSchema

final class SlateRemoteChangeIngestor<Schema: SlateSchema>: @unchecked Sendable {
    private weak var owner: SlateStoreOwner<Schema>?
    private let tokenStore: SlateHistoryTokenStore
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var ingestionHookForTesting: (@Sendable () -> Void)?

    init(
        owner: SlateStoreOwner<Schema>,
        tokenStore: SlateHistoryTokenStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.owner = owner
        self.tokenStore = tokenStore
        self.notificationCenter = notificationCenter
    }

    deinit {
        stop()
    }

    func start() {
        guard let coordinator = owner?.coordinator else {
            return
        }

        lock.lock()
        if observer != nil {
            lock.unlock()
            return
        }
        let newObserver = notificationCenter.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: nil
        ) { [weak self] _ in
            self?.ingestRemoteChangeFromNotification()
        }
        observer = newObserver
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let currentObserver = observer
        observer = nil
        lock.unlock()

        if let currentObserver {
            notificationCenter.removeObserver(currentObserver)
        }
    }

    func ingestRemoteChangeForTesting() async throws {
        try await ingestRemoteChange()
    }

    func setIngestionHookForTesting(_ hook: (@Sendable () -> Void)?) {
        lock.lock()
        ingestionHookForTesting = hook
        lock.unlock()
    }

    var isObservingForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observer != nil
    }

    private func ingestRemoteChangeFromNotification() {
        Task { [weak self] in
            try? await self?.ingestRemoteChange()
        }
    }

    private func ingestRemoteChange() async throws {
        _ = tokenStore
        _ = try await requireLoadedOwner()

        currentIngestionHookForTesting()?()
    }

    private func currentIngestionHookForTesting() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let hook = ingestionHookForTesting
        return hook
    }

    private func requireLoadedOwner() async throws -> SlateStoreOwner<Schema> {
        while true {
            guard let owner else {
                throw SlateError.closed
            }

            switch owner.loadState {
            case .loaded:
                return owner
            case .failed(let error):
                throw error.slateError
            case .loading:
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}
