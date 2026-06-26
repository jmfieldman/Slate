@preconcurrency import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@Suite(.serialized)
struct SlateCloudKitLiveTests {
    @Test(.enabled(if: SlateCloudKitLiveEnvironment.configuration != nil, "requires live CloudKit environment"))
    func cloudKitMirroredStoreExportsUUIDDistinctWrite() async throws {
        let configuration = try #require(SlateCloudKitLiveEnvironment.configuration)
        let directory = try temporaryDirectory(prefix: "SlateCloudKitLive")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let slate = Slate<TestCloudKitRuntimeSchema>(
            storeURL: directory.appendingPathComponent("Live.sqlite"),
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitMirrored(containerIdentifier: configuration.containerIdentifier)
        )
        try slate.configure()
        let owner = try slateStoreOwner(for: slate)
        let container = try #require(owner.cloudKitContainer)
        let exportStartDate = Date()
        let title = "slate-live-\(UUID().uuidString)"

        try await slate.mutate { context in
            let record = context.create(DatabaseTestCloudKitRuntimeRecord.self)
            record.title = title
        }

        let storeIdentifiers = Set(container.persistentStoreCoordinator.persistentStores.compactMap(\.identifier))
        let event = try await waitForSuccessfulExport(
            in: container,
            storeIdentifiers: storeIdentifiers,
            after: exportStartDate,
            timeout: 60
        )

        #expect(event.type == NSPersistentCloudKitContainer.EventType.export)
        #expect(event.succeeded)
        #expect(event.error == nil)
        #expect(event.endDate != nil)
    }
}

private struct SlateCloudKitLiveConfiguration: Sendable {
    let containerIdentifier: String
}

private enum SlateCloudKitLiveEnvironment {
    static var configuration: SlateCloudKitLiveConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SLATE_CLOUDKIT_LIVE"] == "1" else {
            return nil
        }
        let containerIdentifier = environment["SLATE_CLOUDKIT_CONTAINER_IDENTIFIER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !containerIdentifier.isEmpty else {
            return nil
        }
        return SlateCloudKitLiveConfiguration(containerIdentifier: containerIdentifier)
    }
}

private func waitForSuccessfulExport(
    in container: NSPersistentCloudKitContainer,
    storeIdentifiers: Set<String>,
    after startDate: Date,
    timeout: TimeInterval
) async throws -> NSPersistentCloudKitContainer.Event {
    let deadline = Date().addingTimeInterval(timeout)
    var lastExportError: Error?

    while Date() < deadline {
        let events = try fetchCloudKitEvents(in: container, after: startDate)
        if let event = events.first(where: { event in
            event.type == .export
                && event.succeeded
                && event.error == nil
                && event.endDate != nil
                && storeIdentifiers.contains(event.storeIdentifier)
        }) {
            return event
        }
        lastExportError = events.last(where: { event in
            event.type == .export
                && event.error != nil
                && storeIdentifiers.contains(event.storeIdentifier)
        })?.error
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    if let lastExportError {
        throw lastExportError
    }
    throw SlateCloudKitLiveTimeoutError(timeout: timeout)
}

private func fetchCloudKitEvents(
    in container: NSPersistentCloudKitContainer,
    after startDate: Date
) throws -> [NSPersistentCloudKitContainer.Event] {
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = container.persistentStoreCoordinator

    return try context.performAndWait {
        let request = NSPersistentCloudKitContainerEventRequest.fetchEvents(after: startDate)
        request.resultType = .events
        let result = try container.persistentStoreCoordinator.execute(
            request,
            with: context
        ) as? NSPersistentCloudKitContainerEventResult
        return result?.result as? [NSPersistentCloudKitContainer.Event] ?? []
    }
}

private struct SlateCloudKitLiveTimeoutError: Error, CustomStringConvertible {
    let timeout: TimeInterval

    var description: String {
        "Timed out after \(timeout) seconds waiting for a successful CloudKit export event"
    }
}

private func temporaryDirectory(prefix: String) throws -> URL {
    let directory = URL(
        fileURLWithPath: NSTemporaryDirectory(),
        isDirectory: true
    ).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func slateStoreOwner<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> SlateStoreOwner<Schema> {
    let mirror = Mirror(reflecting: slate)
    for child in mirror.children where child.label == "owner" {
        if let owner = child.value as? SlateStoreOwner<Schema> {
            return owner
        }
    }
    throw NSError(domain: "SlateCloudKitLiveTests", code: -1)
}
