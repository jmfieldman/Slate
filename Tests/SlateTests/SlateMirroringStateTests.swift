import CloudKit
import CoreData
import Foundation
import Observation
import SlateSchema
import Testing
@testable import Slate

private let mirroringContainerIdentifierPrefix = "iCloud.com.example.SlateMirroring"

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

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
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

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
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

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
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

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
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

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
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

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
            try slate.configure()
        }

        #expect(provider.callCount == 0)
        #expect(slate.accountStatus == .unavailable)
        await slate.close()
    }

    @Test
    func importBeginSetsIsImportingTrue() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringImportBegin")
        let events = CloudKitEventObserverProbe()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        events.post(importEvent(endDate: nil))
        try await waitForImporting(true, on: slate)

        #expect(slate.lastImportError == nil)
        await slate.close()
    }

    @Test
    func overlappingImportsKeepIsImportingTrueUntilBothComplete() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringOverlappingImports")
        let events = CloudKitEventObserverProbe()
        let firstID = UUID()
        let secondID = UUID()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        events.post(importEvent(identifier: firstID, endDate: nil))
        events.post(importEvent(identifier: secondID, endDate: nil))
        try await waitForImporting(true, on: slate)

        events.post(importEvent(identifier: firstID, endDate: Date()))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(slate.isImporting)

        events.post(importEvent(identifier: secondID, endDate: Date()))
        try await waitForImporting(false, on: slate)

        await slate.close()
    }

    @Test
    func failedImportStoresLastImportError() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringImportError")
        let events = CloudKitEventObserverProbe()
        let importID = UUID()
        let error = ImportEventProbeError()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        events.post(importEvent(identifier: importID, endDate: nil))
        try await waitForImporting(true, on: slate)
        events.post(importEvent(identifier: importID, endDate: Date(), error: error))
        try await waitForImporting(false, on: slate)
        try await waitForLastImportError(error, on: slate)

        #expect((slate.lastImportError as? ImportEventProbeError) === error)
        await slate.close()
    }

    @Test
    func laterSuccessfulImportDoesNotClearLastImportError() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringRetainsImportError")
        let events = CloudKitEventObserverProbe()
        let failedID = UUID()
        let successfulID = UUID()
        let error = ImportEventProbeError()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        events.post(importEvent(identifier: failedID, endDate: nil))
        events.post(importEvent(identifier: failedID, endDate: Date(), error: error))
        try await waitForLastImportError(error, on: slate)
        #expect((slate.lastImportError as? ImportEventProbeError) === error)

        events.post(importEvent(identifier: successfulID, endDate: nil))
        try await waitForImporting(true, on: slate)
        events.post(importEvent(identifier: successfulID, endDate: Date()))
        try await waitForImporting(false, on: slate)

        #expect((slate.lastImportError as? ImportEventProbeError) === error)
        await slate.close()
    }

    @Test
    func importEventDuringLoadBoundaryIsCaptured() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringImportDuringLoad")
        let events = CloudKitEventObserverProbe()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try SlateCloudKitContainer.withLoadPersistentStoresOverride(
                matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
                { _, completion in
                    events.post(importEvent(endDate: nil))
                    completion(nil)
                }
            ) {
                try slate.configure()
            }
        }

        try await waitForImporting(true, on: slate)
        await slate.close()
    }

    @Test
    func exportAndSetupEventsDoNotChangeIsImporting() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringIgnoredEvents")
        let events = CloudKitEventObserverProbe()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        events.post(event(type: .export, endDate: nil))
        events.post(event(type: .setup, endDate: nil))
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(!slate.isImporting)
        #expect(slate.lastImportError == nil)
        await slate.close()
    }

    @Test
    func releasingCloudKitSlateUnregistersImportEventSink() throws {
        var slate: Slate<TestCloudKitRuntimeSchema>? = try makeCloudKitSlate(prefix: "SlateMirroringImportDeinit")
        let events = CloudKitEventObserverProbe()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(try #require(slate))
            #expect(events.registrationCount == 1)
            #expect(events.activeHandlerCount == 1)

            slate = nil
        }

        #expect(events.activeHandlerCount == 0)
    }

    @Test
    func cloudKitSlateIsMergingFollowsOwnerMergeState() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringMergeState")

        try configureWithSuccessfulCloudKitLoad(slate)
        let owner = try slateStoreOwner(for: slate)

        #expect(!slate.isMerging)

        owner.setIsMerging(true)
        try await waitForMerging(true, on: slate)

        owner.setIsMerging(false)
        try await waitForMerging(false, on: slate)

        await slate.close()
    }

    @Test
    func observingPublicAccountStatusInvalidatesWhenAccountStatusChanges() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringObserveAccountStatus")
        let provider = AccountStatusProviderProbe(statuses: [.available, .restricted])

        try SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }
        try await waitForAccountStatus(.available, on: slate)

        let observation = ObservationProbe()
        withObservationTracking {
            _ = slate.accountStatus
        } onChange: {
            observation.recordChange()
        }

        SlateCloudKitContainer.withAccountStatusProviderOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            provider.provider
        ) {
            NotificationCenter.default.post(name: Notification.Name.CKAccountChanged, object: nil)
        }
        try await observation.waitForChange()
        try await waitForAccountStatus(.restricted, on: slate)

        #expect(provider.callCount == 2)
        await slate.close()
    }

    @Test
    func observingPublicImportingInvalidatesWhenImportStateChanges() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringObserveImporting")
        let events = CloudKitEventObserverProbe()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        let observation = ObservationProbe()
        withObservationTracking {
            _ = slate.isImporting
        } onChange: {
            observation.recordChange()
        }

        events.post(importEvent(endDate: nil))
        try await observation.waitForChange()
        try await waitForImporting(true, on: slate)

        await slate.close()
    }

    @Test
    func observingPublicLastImportErrorInvalidatesWhenImportErrorChanges() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringObserveImportError")
        let events = CloudKitEventObserverProbe()
        let error = ImportEventProbeError()

        try SlateCloudKitContainer.withEventObserverInstallerOverride(
            matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
            events.installer
        ) {
            try configureWithSuccessfulCloudKitLoad(slate)
        }

        let observation = ObservationProbe()
        withObservationTracking {
            _ = slate.lastImportError
        } onChange: {
            observation.recordChange()
        }

        events.post(importEvent(endDate: Date(), error: error))
        try await observation.waitForChange()
        try await waitForLastImportError(error, on: slate)

        await slate.close()
    }

    @Test
    func observingPublicMergingInvalidatesWhenMergeStateChanges() async throws {
        let slate = try makeCloudKitSlate(prefix: "SlateMirroringObserveMerging")

        try configureWithSuccessfulCloudKitLoad(slate)
        let owner = try slateStoreOwner(for: slate)

        let observation = ObservationProbe()
        withObservationTracking {
            _ = slate.isMerging
        } onChange: {
            observation.recordChange()
        }

        owner.setIsMerging(true)
        try await observation.waitForChange()
        try await waitForMerging(true, on: slate)

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
        storageMode: .cloudKitMirrored(containerIdentifier: "\(mirroringContainerIdentifierPrefix).\(prefix)")
    )
}

private func configureWithSuccessfulCloudKitLoad<Schema: SlateSchema>(_ slate: Slate<Schema>) throws {
    try SlateCloudKitContainer.withLoadPersistentStoresOverride(
        matchingContainerIdentifierPrefix: mirroringContainerIdentifierPrefix,
        { _, completion in
            completion(nil)
        }
    ) {
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

private func waitForImporting<Schema: SlateSchema>(
    _ expectedValue: Bool,
    on slate: Slate<Schema>
) async throws {
    for _ in 0..<40 {
        if slate.isImporting == expectedValue {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for isImporting \(expectedValue); current value \(slate.isImporting)")
}

private func waitForMerging<Schema: SlateSchema>(
    _ expectedValue: Bool,
    on slate: Slate<Schema>
) async throws {
    for _ in 0..<40 {
        if slate.isMerging == expectedValue {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for isMerging \(expectedValue); current value \(slate.isMerging)")
}

private func waitForLastImportError<Schema: SlateSchema>(
    _ expectedError: ImportEventProbeError,
    on slate: Slate<Schema>
) async throws {
    for _ in 0..<40 {
        if (slate.lastImportError as? ImportEventProbeError) === expectedError {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for lastImportError to publish")
}

private func importEvent(
    identifier: UUID = UUID(),
    endDate: Date?,
    error: (any Error)? = nil
) -> SlateCloudKitContainer.EventSnapshot {
    event(identifier: identifier, type: .import, endDate: endDate, error: error)
}

private func event(
    identifier: UUID = UUID(),
    type: NSPersistentCloudKitContainer.EventType,
    endDate: Date?,
    error: (any Error)? = nil
) -> SlateCloudKitContainer.EventSnapshot {
    SlateCloudKitContainer.EventSnapshot(
        identifier: identifier,
        type: type,
        endDate: endDate,
        error: error
    )
}

private func slateStoreOwner<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> SlateStoreOwner<Schema> {
    let mirror = Mirror(reflecting: slate)
    for child in mirror.children where child.label == "owner" {
        if let owner = child.value as? SlateStoreOwner<Schema> {
            return owner
        }
    }
    throw NSError(domain: "SlateMirroringStateTests", code: -1)
}

private struct AccountStatusProbeError: Error {}

private final class ImportEventProbeError: Error {}

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
        guard containerIdentifier.hasPrefix("iCloud.com.example.SlateMirroring") else {
            completion(SlateCloudKitContainer.AccountStatusResult(status: .couldNotDetermine, error: nil))
            return
        }

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
        guard containerIdentifier.hasPrefix("iCloud.com.example.SlateMirroring") else {
            completion(SlateCloudKitContainer.AccountStatusResult(status: .couldNotDetermine, error: nil))
            return
        }

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

private final class CloudKitEventObserverProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [UUID: @Sendable (SlateCloudKitContainer.EventSnapshot) -> Void] = [:]
    private var storedRegistrationCount = 0

    var registrationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRegistrationCount
    }

    var activeHandlerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }

    func installer(
        container: NSPersistentCloudKitContainer,
        handler: @escaping @Sendable (SlateCloudKitContainer.EventSnapshot) -> Void
    ) -> SlateCloudKitContainer.EventObserverToken {
        _ = container
        let id = UUID()
        lock.lock()
        storedRegistrationCount += 1
        handlers[id] = handler
        lock.unlock()

        return SlateCloudKitContainer.EventObserverToken { [weak self] in
            self?.lock.lock()
            self?.handlers.removeValue(forKey: id)
            self?.lock.unlock()
        }
    }

    func post(_ event: SlateCloudKitContainer.EventSnapshot) {
        lock.lock()
        let capturedHandlers = Array(handlers.values)
        lock.unlock()

        for handler in capturedHandlers {
            handler(event)
        }
    }
}

private final class ObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var changeCount = 0

    private var didChange: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changeCount > 0
    }

    func recordChange() {
        lock.lock()
        changeCount += 1
        lock.unlock()
    }

    func waitForChange() async throws {
        for _ in 0..<40 {
            if didChange {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for Observation invalidation")
    }
}
