import CloudKit
import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@Suite(.serialized)
struct SlateMirroringStateTests {
    @Test(arguments: [
        (CKAccountStatus.available, SlateAccountStatus.available),
        (CKAccountStatus.noAccount, SlateAccountStatus.unavailable),
        (CKAccountStatus.temporarilyUnavailable, SlateAccountStatus.unavailable),
        (CKAccountStatus.restricted, SlateAccountStatus.restricted),
        (CKAccountStatus.couldNotDetermine, SlateAccountStatus.couldNotDetermine),
    ])
    func mapsKnownCloudKitAccountStatuses(
        cloudKitStatus: CKAccountStatus,
        slateStatus: SlateAccountStatus
    ) {
        #expect(SlateAccountStatus(cloudKitStatus: cloudKitStatus) == slateStatus)
    }

    @Test
    func mapsUnknownCloudKitAccountStatusToCouldNotDetermine() throws {
        let futureStatus = try #require(CKAccountStatus(rawValue: 999))

        #expect(SlateAccountStatus(cloudKitStatus: futureStatus) == .couldNotDetermine)
    }

    @Test
    func neutralInitializerUsesLocalModeDefaults() {
        let state = SlateMirroringState()

        #expect(state.accountStatus == .unavailable)
        #expect(!state.isImporting)
        #expect(!state.isMerging)
        #expect(state.lastImportError == nil)
    }

    @Test
    func localSlateExposesNeutralMirroringPropertiesDirectly() {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)

        #expect(slate.accountStatus == .unavailable)
        #expect(!slate.isImporting)
        #expect(!slate.isMerging)
        #expect(slate.lastImportError == nil)
    }

    @Test
    func cloudKitSlateUpdatesAccountStatusAfterLoad() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringInitialAccountStatus")
        let provider = AccountStatusProviderProbe(statuses: [.available])

        try SlateCloudKitContainer.withAccountStatusProviderOverride(provider.provider) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }
        try await waitForAccountStatus(.available, on: slate)

        #expect(provider.callCount == 1)
        await slate.close()
    }

    @Test
    func cloudKitAccountStatusErrorPublishesCouldNotDetermine() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringAccountStatusError")
        let provider = AccountStatusProviderProbe(results: [
            SlateCloudKitContainer.AccountStatusResult(status: nil, error: AccountStatusProbeError()),
        ])

        try SlateCloudKitContainer.withAccountStatusProviderOverride(provider.provider) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }
        try await waitForAccountStatus(.couldNotDetermine, on: slate)

        #expect(provider.callCount == 1)
        await slate.close()
    }

    @Test
    func accountChangeNotificationRequeriesAndPublishesNewStatus() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringAccountChange")
        let provider = AccountStatusProviderProbe(statuses: [.available, .restricted])

        try SlateCloudKitContainer.withAccountStatusProviderOverride(provider.provider) {
            try configureWithSuccessfulCloudKitLoad(slate)
            NotificationCenter.default.post(name: Notification.Name.CKAccountChanged, object: nil)
        }
        try await waitForAccountStatus(.restricted, on: slate)

        #expect(provider.callCount == 2)
        await slate.close()
    }

    @Test
    func olderAccountStatusCompletionDoesNotOverwriteNewerRefresh() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringAccountStatusOrdering")
        let provider = DeferredAccountStatusProviderProbe()

        try SlateCloudKitContainer.withAccountStatusProviderOverride(provider.provider) {
            try configureWithSuccessfulCloudKitLoad(slate)
            NotificationCenter.default.post(name: Notification.Name.CKAccountChanged, object: nil)
        }
        try await waitForPendingAccountStatusRequests(2, provider: provider)

        provider.completeRequest(
            at: 1,
            with: SlateCloudKitContainer.AccountStatusResult(status: .restricted, error: nil)
        )
        try await waitForAccountStatus(.restricted, on: slate)

        provider.completeRequest(
            at: 0,
            with: SlateCloudKitContainer.AccountStatusResult(status: .available, error: nil)
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(slate.accountStatus == .restricted)
        #expect(provider.callCount == 2)
        await slate.close()
    }

    @Test
    func releasingCloudKitSlateUnregistersAccountStatusSink() throws {
        var slate: Slate<TestCloudKitRuntimeSchema>? = try makeCloudKitSlate(prefix: "SlateMirroringAccountStatusDeinit")
        let provider = AccountStatusProviderProbe(statuses: [.available, .restricted])

        try SlateCloudKitContainer.withAccountStatusProviderOverride(provider.provider) {
            try configureWithSuccessfulCloudKitLoad(try #require(slate))
            #expect(provider.callCount == 1)

            slate = nil
            NotificationCenter.default.post(name: Notification.Name.CKAccountChanged, object: nil)
        }

        #expect(provider.callCount == 1)
    }

    @Test
    func localSlateDoesNotAskForCloudKitAccountStatus() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        let provider = AccountStatusProviderProbe(statuses: [.available])

        try SlateCloudKitContainer.withAccountStatusProviderOverride(provider.provider) {
            try slate.configure()
        }

        #expect(provider.callCount == 0)
        #expect(slate.accountStatus == .unavailable)
        await slate.close()
    }
}

private func makeCloudKitSlate(prefix: String) throws -> Slate<TestCloudKitRuntimeSchema> {
    let directory = URL(
        fileURLWithPath: NSTemporaryDirectory(),
        isDirectory: true
    ).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return Slate<TestCloudKitRuntimeSchema>(
        storeURL: directory.appendingPathComponent("Test.sqlite"),
        storeType: NSSQLiteStoreType,
        storageMode: .cloudKitMirrored(containerIdentifier: "iCloud.com.example")
    )
}

private func configureWithSuccessfulCloudKitLoad<Schema: SlateSchema>(_ slate: Slate<Schema>) throws {
    try SlateCloudKitContainer.withLoadPersistentStoresOverride({ _, completion in
        completion(nil)
    }) {
        try slate.configure()
    }
}

private func waitForAccountStatus<Schema: SlateSchema>(
    _ expectedStatus: SlateAccountStatus,
    on slate: Slate<Schema>
) async throws {
    for _ in 0..<40 {
        if slate.accountStatus == expectedStatus {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for account status \(expectedStatus); current value \(slate.accountStatus)")
}

private func waitForPendingAccountStatusRequests(
    _ expectedCount: Int,
    provider: DeferredAccountStatusProviderProbe
) async throws {
    for _ in 0..<40 {
        if provider.pendingRequestCount >= expectedCount {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record(
        "Timed out waiting for \(expectedCount) pending account-status requests; current count \(provider.pendingRequestCount)"
    )
}

private struct AccountStatusProbeError: Error {}

private final class AccountStatusProviderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [SlateCloudKitContainer.AccountStatusResult]
    private var storedCallCount = 0

    init(statuses: [CKAccountStatus]) {
        self.results = statuses.map {
            SlateCloudKitContainer.AccountStatusResult(status: $0, error: nil)
        }
    }

    init(results: [SlateCloudKitContainer.AccountStatusResult]) {
        self.results = results
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallCount
    }

    func provider(
        containerIdentifier: String,
        completion: @escaping @Sendable (SlateCloudKitContainer.AccountStatusResult) -> Void
    ) {
        _ = containerIdentifier
        let result: SlateCloudKitContainer.AccountStatusResult
        lock.lock()
        storedCallCount += 1
        if results.isEmpty {
            result = SlateCloudKitContainer.AccountStatusResult(status: .couldNotDetermine, error: nil)
        } else {
            result = results.removeFirst()
        }
        lock.unlock()

        completion(result)
    }
}

private final class DeferredAccountStatusProviderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [@Sendable (SlateCloudKitContainer.AccountStatusResult) -> Void] = []

    var callCount: Int {
        pendingRequestCount
    }

    var pendingRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }

    func provider(
        containerIdentifier: String,
        completion: @escaping @Sendable (SlateCloudKitContainer.AccountStatusResult) -> Void
    ) {
        _ = containerIdentifier
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    func completeRequest(
        at index: Int,
        with result: SlateCloudKitContainer.AccountStatusResult
    ) {
        lock.lock()
        let completion = completions[index]
        lock.unlock()

        completion(result)
    }
}
