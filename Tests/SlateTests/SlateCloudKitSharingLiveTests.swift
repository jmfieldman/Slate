@preconcurrency import CloudKit
@preconcurrency import CoreData
import Foundation
import Testing
@testable import Slate

@Suite(.serialized)
struct SlateCloudKitSharingLiveTests {
    @Test(.enabled(
        if: SlateCloudKitSharingLiveEnvironment.configuration(for: .create) != nil,
        "requires owner create env. Example: SLATE_CLOUDKIT_LIVE=1 SLATE_CLOUDKIT_CONTAINER_IDENTIFIER=iCloud.com.example.app SLATE_CLOUDKIT_SHARE_PHASE=create SLATE_CLOUDKIT_SHARE_HANDOFF_PATH=/tmp/slate-share.json SLATE_CLOUDKIT_INVITEE_EMAIL=invitee@example.com swift test --filter SlateCloudKitSharingLiveTests/createPhase"
    ))
    func createPhase() async throws {
        let configuration = try #require(SlateCloudKitSharingLiveEnvironment.configuration(for: .create))
        let runID = "slate-share-live-\(UUID().uuidString)"
        let rootTitle = "\(runID)-root"
        let slate = try makeLiveSharingSlate(
            storeURL: configuration.ownerStoreURL,
            containerIdentifier: configuration.containerIdentifier
        )

        let root = try await slate.mutate { context in
            let record = context.create(DatabaseTestCloudKitRuntimeRecord.self)
            record.title = rootTitle
            return record.slateObject
        }
        let sharing = try slate.sharing
        let (share, container) = try await sharing.prepareShare(
            for: root,
            title: runID
        )
        let participant = try await liveParticipant(
            using: container,
            emailAddress: configuration.inviteeEmail,
            phoneNumber: configuration.inviteePhone
        )
        participant.permission = .readOnly
        share.addParticipant(participant)
        try await saveLiveShare(share, in: container.privateCloudDatabase)
        guard let shareURL = share.url else {
            throw SlateCloudKitSharingLiveError("create phase saved a share without a URL")
        }

        let handoff = SlateCloudKitSharingLiveHandoff(
            runID: runID,
            rootObjectIdentity: SlateCloudKitSharingLiveRootIdentity(
                entity: DatabaseTestCloudKitRuntimeRecord.slateEntityName,
                objectURI: root.slateID.uriRepresentation().absoluteString,
                title: rootTitle
            ),
            shareURL: shareURL,
            ownerStorePath: configuration.ownerStoreURL.standardizedFileURL.path,
            containerIdentifier: configuration.containerIdentifier,
            phases: SlateCloudKitSharingLivePhaseFlags(
                createCompleted: true,
                acceptCompleted: false,
                stopCompleted: false
            ),
            cleanup: SlateCloudKitSharingLiveCleanupState(
                stopAttempted: false,
                stopCompleted: false,
                lastErrorDescription: nil
            )
        )
        try writeLiveHandoff(handoff, to: configuration.handoffURL)
    }

    @Test(.enabled(
        if: SlateCloudKitSharingLiveEnvironment.configuration(for: .accept) != nil,
        "requires invitee accept env. Example: SLATE_CLOUDKIT_LIVE=1 SLATE_CLOUDKIT_CONTAINER_IDENTIFIER=iCloud.com.example.app SLATE_CLOUDKIT_SHARE_PHASE=accept SLATE_CLOUDKIT_SHARE_HANDOFF_PATH=/tmp/slate-share.json swift test --filter SlateCloudKitSharingLiveTests/acceptPhase"
    ))
    func acceptPhase() async throws {
        let configuration = try #require(SlateCloudKitSharingLiveEnvironment.configuration(for: .accept))
        var handoff = try readLiveHandoff(from: configuration.handoffURL)
        try handoff.validate(
            expectedContainerIdentifier: configuration.containerIdentifier,
            requiredPriorPhase: .create
        )

        let metadata = try await shareMetadata(
            for: handoff.shareURL,
            containerIdentifier: handoff.containerIdentifier
        )
        let slate = try makeLiveSharingSlate(
            storeURL: configuration.inviteeStoreURL,
            containerIdentifier: handoff.containerIdentifier
        )

        try await slate.sharing.acceptShare(metadata)
        handoff.phases.acceptCompleted = true
        try writeLiveHandoff(handoff, to: configuration.handoffURL)
    }

    @Test(.enabled(
        if: SlateCloudKitSharingLiveEnvironment.configuration(for: .stop) != nil,
        "requires owner stop env. Example: SLATE_CLOUDKIT_LIVE=1 SLATE_CLOUDKIT_CONTAINER_IDENTIFIER=iCloud.com.example.app SLATE_CLOUDKIT_SHARE_PHASE=stop SLATE_CLOUDKIT_SHARE_HANDOFF_PATH=/tmp/slate-share.json swift test --filter SlateCloudKitSharingLiveTests/stopPhase"
    ))
    func stopPhase() async throws {
        let configuration = try #require(SlateCloudKitSharingLiveEnvironment.configuration(for: .stop))
        var handoff = try readLiveHandoff(from: configuration.handoffURL)
        try handoff.validate(
            expectedContainerIdentifier: configuration.containerIdentifier,
            requiredPriorPhase: .accept
        )
        handoff.cleanup.stopAttempted = true
        try writeLiveHandoff(handoff, to: configuration.handoffURL)

        do {
            let slate = try makeLiveSharingSlate(
                storeURL: URL(fileURLWithPath: handoff.ownerStorePath),
                containerIdentifier: handoff.containerIdentifier
            )
            let root = try await findLiveRootObject(
                in: slate,
                title: handoff.rootObjectIdentity.title
            )
            try await slate.sharing.stopSharing(root)
            let remainingShare = try await slate.sharing.share(for: root)
            #expect(remainingShare == nil)

            handoff.phases.stopCompleted = true
            handoff.cleanup.stopCompleted = true
            handoff.cleanup.lastErrorDescription = nil
            try writeLiveHandoff(handoff, to: configuration.handoffURL)
        } catch {
            handoff.cleanup.lastErrorDescription = String(describing: error)
            try? writeLiveHandoff(handoff, to: configuration.handoffURL)
            throw error
        }
    }
}

private enum SlateCloudKitSharingLivePhase: String, Codable, Sendable {
    case create
    case accept
    case stop
}

private struct SlateCloudKitSharingLiveConfiguration: Sendable {
    let phase: SlateCloudKitSharingLivePhase
    let containerIdentifier: String
    let handoffURL: URL
    let ownerStoreURL: URL
    let inviteeStoreURL: URL
    let inviteeEmail: String?
    let inviteePhone: String?
}

private enum SlateCloudKitSharingLiveEnvironment {
    static func configuration(for expectedPhase: SlateCloudKitSharingLivePhase) -> SlateCloudKitSharingLiveConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SLATE_CLOUDKIT_LIVE"] == "1" else {
            return nil
        }
        guard phase(in: environment) == expectedPhase else {
            return nil
        }
        let containerIdentifier = trimmed("SLATE_CLOUDKIT_CONTAINER_IDENTIFIER", in: environment)
        guard !containerIdentifier.isEmpty else {
            return nil
        }
        let handoffPath = trimmed("SLATE_CLOUDKIT_SHARE_HANDOFF_PATH", in: environment)
        guard !handoffPath.isEmpty else {
            return nil
        }

        let handoffURL = URL(fileURLWithPath: handoffPath).standardizedFileURL
        let ownerStoreURL = storeURL(
            environmentKey: "SLATE_CLOUDKIT_OWNER_STORE_PATH",
            fallbackDirectoryPrefix: "SlateCloudKitSharingOwnerLive",
            fallbackStoreName: "Owner.sqlite",
            environment: environment
        )
        let inviteeStoreURL = storeURL(
            environmentKey: "SLATE_CLOUDKIT_INVITEE_STORE_PATH",
            fallbackDirectoryPrefix: "SlateCloudKitSharingInviteeLive",
            fallbackStoreName: "Invitee.sqlite",
            environment: environment
        )
        let inviteeEmail = optionalTrimmed("SLATE_CLOUDKIT_INVITEE_EMAIL", in: environment)
        let inviteePhone = optionalTrimmed("SLATE_CLOUDKIT_INVITEE_PHONE", in: environment)

        if expectedPhase == .create, inviteeEmail == nil, inviteePhone == nil {
            return nil
        }

        return SlateCloudKitSharingLiveConfiguration(
            phase: expectedPhase,
            containerIdentifier: containerIdentifier,
            handoffURL: handoffURL,
            ownerStoreURL: ownerStoreURL,
            inviteeStoreURL: inviteeStoreURL,
            inviteeEmail: inviteeEmail,
            inviteePhone: inviteePhone
        )
    }

    private static func phase(in environment: [String: String]) -> SlateCloudKitSharingLivePhase? {
        SlateCloudKitSharingLivePhase(rawValue: trimmed("SLATE_CLOUDKIT_SHARE_PHASE", in: environment))
    }

    private static func trimmed(_ key: String, in environment: [String: String]) -> String {
        environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func optionalTrimmed(_ key: String, in environment: [String: String]) -> String? {
        let value = trimmed(key, in: environment)
        return value.isEmpty ? nil : value
    }

    private static func storeURL(
        environmentKey: String,
        fallbackDirectoryPrefix: String,
        fallbackStoreName: String,
        environment: [String: String]
    ) -> URL {
        let configuredPath = trimmed(environmentKey, in: environment)
        if !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath).standardizedFileURL
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(fallbackDirectoryPrefix)-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent(fallbackStoreName)
    }
}

private struct SlateCloudKitSharingLiveHandoff: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var runID: String
    var rootObjectIdentity: SlateCloudKitSharingLiveRootIdentity
    var shareURL: URL
    var ownerStorePath: String
    var containerIdentifier: String
    var phases: SlateCloudKitSharingLivePhaseFlags
    var cleanup: SlateCloudKitSharingLiveCleanupState

    init(
        runID: String,
        rootObjectIdentity: SlateCloudKitSharingLiveRootIdentity,
        shareURL: URL,
        ownerStorePath: String,
        containerIdentifier: String,
        phases: SlateCloudKitSharingLivePhaseFlags,
        cleanup: SlateCloudKitSharingLiveCleanupState
    ) {
        self.schemaVersion = 1
        self.runID = runID
        self.rootObjectIdentity = rootObjectIdentity
        self.shareURL = shareURL
        self.ownerStorePath = ownerStorePath
        self.containerIdentifier = containerIdentifier
        self.phases = phases
        self.cleanup = cleanup
    }

    func validate(
        expectedContainerIdentifier: String,
        requiredPriorPhase: SlateCloudKitSharingLivePhase
    ) throws {
        guard schemaVersion == 1 else {
            throw SlateCloudKitSharingLiveError("unsupported handoff schema version \(schemaVersion)")
        }
        guard containerIdentifier == expectedContainerIdentifier else {
            throw SlateCloudKitSharingLiveError(
                "handoff container \(containerIdentifier) does not match \(expectedContainerIdentifier)"
            )
        }
        guard !runID.isEmpty,
              !rootObjectIdentity.title.isEmpty,
              !ownerStorePath.isEmpty else {
            throw SlateCloudKitSharingLiveError("handoff is missing required root or owner fields")
        }

        switch requiredPriorPhase {
        case .create:
            guard phases.createCompleted else {
                throw SlateCloudKitSharingLiveError("handoff create phase is not complete")
            }
        case .accept:
            guard phases.createCompleted, phases.acceptCompleted else {
                throw SlateCloudKitSharingLiveError("handoff accept phase is not complete")
            }
        case .stop:
            guard phases.stopCompleted else {
                throw SlateCloudKitSharingLiveError("handoff stop phase is not complete")
            }
        }
    }
}

private struct SlateCloudKitSharingLiveRootIdentity: Codable, Equatable, Sendable {
    var entity: String
    var objectURI: String
    var title: String
}

private struct SlateCloudKitSharingLivePhaseFlags: Codable, Equatable, Sendable {
    var createCompleted: Bool
    var acceptCompleted: Bool
    var stopCompleted: Bool
}

private struct SlateCloudKitSharingLiveCleanupState: Codable, Equatable, Sendable {
    var stopAttempted: Bool
    var stopCompleted: Bool
    var lastErrorDescription: String?
}

private func makeLiveSharingSlate(
    storeURL: URL,
    containerIdentifier: String
) throws -> Slate<TestCloudKitRuntimeSchema> {
    try FileManager.default.createDirectory(
        at: storeURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let slate = Slate<TestCloudKitRuntimeSchema>(
        storeURL: storeURL,
        storeType: NSSQLiteStoreType,
        storageMode: .cloudKitShared(containerIdentifier: containerIdentifier)
    )
    try slate.configure()
    return slate
}

private func liveParticipant(
    using container: CKContainer,
    emailAddress: String?,
    phoneNumber: String?
) async throws -> CKShare.Participant {
    if let emailAddress {
        let results = try await container.shareParticipants(forEmailAddresses: [emailAddress])
        return try participantResult(for: emailAddress, in: results)
    }

    guard let phoneNumber else {
        throw SlateCloudKitSharingLiveError("create phase requires an invitee email or phone number")
    }
    let results = try await container.shareParticipants(forPhoneNumbers: [phoneNumber])
    return try participantResult(for: phoneNumber, in: results)
}

private func participantResult(
    for input: String,
    in results: [String: Result<CKShare.Participant, Error>]
) throws -> CKShare.Participant {
    guard let result = results[input] else {
        throw SlateCloudKitSharingLiveError("CloudKit returned no participant result for \(input)")
    }
    switch result {
    case .success(let participant):
        return participant
    case .failure(let error):
        throw error
    }
}

private func saveLiveShare(_ share: CKShare, in database: CKDatabase) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let operation = CKModifyRecordsOperation(
            recordsToSave: [share],
            recordIDsToDelete: nil
        )
        operation.savePolicy = .changedKeys
        operation.isAtomic = true
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
        database.add(operation)
    }
}

private func shareMetadata(
    for shareURL: URL,
    containerIdentifier: String
) async throws -> CKShare.Metadata {
    let container = CKContainer(identifier: containerIdentifier)
    let results = try await container.shareMetadatas(for: [shareURL])
    guard let result = results[shareURL] else {
        throw SlateCloudKitSharingLiveError("CloudKit returned no share metadata for \(shareURL.absoluteString)")
    }
    switch result {
    case .success(let metadata):
        return metadata
    case .failure(let error):
        throw error
    }
}

private func findLiveRootObject(
    in slate: Slate<TestCloudKitRuntimeSchema>,
    title: String
) async throws -> TestCloudKitRuntimeRecord {
    let records = try await slate.many(TestCloudKitRuntimeRecord.self)
    guard let root = records.first(where: { $0.title == title }) else {
        throw SlateCloudKitSharingLiveError("could not find root object titled \(title)")
    }
    return root
}

private func readLiveHandoff(from url: URL) throws -> SlateCloudKitSharingLiveHandoff {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(SlateCloudKitSharingLiveHandoff.self, from: data)
}

private func writeLiveHandoff(
    _ handoff: SlateCloudKitSharingLiveHandoff,
    to url: URL
) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(handoff)
    try data.write(to: url, options: [.atomic])
}

private struct SlateCloudKitSharingLiveError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
