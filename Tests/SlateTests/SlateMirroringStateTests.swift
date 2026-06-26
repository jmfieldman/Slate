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

private final class AccountStatusProviderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CKAccountStatus]
    private var storedCallCount = 0

    init(statuses: [CKAccountStatus]) {
        self.statuses = statuses
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
        let status: CKAccountStatus
        lock.lock()
        storedCallCount += 1
        if statuses.isEmpty {
            status = .couldNotDetermine
        } else {
            status = statuses.removeFirst()
        }
        lock.unlock()

        completion(SlateCloudKitContainer.AccountStatusResult(status: status, error: nil))
    }
}
