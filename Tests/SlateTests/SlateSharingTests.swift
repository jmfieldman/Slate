import CloudKit
import Foundation
import Testing
@testable import Slate

@Suite
struct SlateSharingTests {
    @Test
    func shareAndParticipantConstructAndCompareByValue() throws {
        let owner = SlateParticipant(
            displayName: "Owner",
            role: .owner,
            permission: .readWrite,
            acceptanceStatus: .accepted
        )
        let participant = SlateParticipant(
            displayName: "Reader",
            role: .privateUser,
            permission: .readOnly,
            acceptanceStatus: .pending
        )
        let url = URL(string: "https://example.com/share")!
        let share = SlateShare(
            url: url,
            title: "Shared Slate",
            owner: owner,
            participants: [participant],
            currentUserPermission: .readWrite
        )

        #expect(owner == SlateParticipant(
            displayName: "Owner",
            role: .owner,
            permission: .readWrite,
            acceptanceStatus: .accepted
        ))
        #expect(participant != owner)
        #expect(share == SlateShare(
            url: url,
            title: "Shared Slate",
            owner: owner,
            participants: [participant],
            currentUserPermission: .readWrite
        ))
        #expect(share != SlateShare(
            url: url,
            title: "Different Slate",
            owner: owner,
            participants: [participant],
            currentUserPermission: .readWrite
        ))
    }

    @Test
    func sharingEnumsExposeApprovedCases() {
        let permissions: [SlateSharePermission] = [.unknown, .none, .readOnly, .readWrite]
        let roles: [SlateShareRole] = [.unknown, .owner, .privateUser, .publicUser, .administrator]
        let acceptanceStatuses: [SlateShareAcceptance] = [.unknown, .pending, .accepted, .removed]

        #expect(permissions.count == 4)
        #expect(Set(permissions.map(String.init(describing:))).count == permissions.count)
        #expect(roles.count == 5)
        #expect(Set(roles.map(String.init(describing:))).count == roles.count)
        #expect(acceptanceStatuses.count == 4)
        #expect(Set(acceptanceStatuses.map(String.init(describing:))).count == acceptanceStatuses.count)
    }

    @Test(arguments: [
        (CKShare.ParticipantPermission.unknown, SlateSharePermission.unknown),
        (CKShare.ParticipantPermission.none, SlateSharePermission.none),
        (CKShare.ParticipantPermission.readOnly, SlateSharePermission.readOnly),
        (CKShare.ParticipantPermission.readWrite, SlateSharePermission.readWrite),
    ])
    func mapsKnownCloudKitPermissions(
        cloudKitPermission: CKShare.ParticipantPermission,
        slatePermission: SlateSharePermission
    ) {
        #expect(SlateSharePermission(cloudKitPermission: cloudKitPermission) == slatePermission)
    }

    @Test(arguments: [
        (CKShare.ParticipantRole.unknown, SlateShareRole.unknown),
        (CKShare.ParticipantRole.owner, SlateShareRole.owner),
        (CKShare.ParticipantRole.privateUser, SlateShareRole.privateUser),
        (CKShare.ParticipantRole.publicUser, SlateShareRole.publicUser),
    ])
    func mapsKnownCloudKitRoles(
        cloudKitRole: CKShare.ParticipantRole,
        slateRole: SlateShareRole
    ) {
        #expect(SlateShareRole(cloudKitRole: cloudKitRole) == slateRole)
    }

    @Test
    func mapsCloudKitAdministratorRole() throws {
        let administratorRole = try #require(CKShare.ParticipantRole(rawValue: 2))

        #expect(SlateShareRole(cloudKitRole: administratorRole) == .administrator)
    }

    @Test(arguments: [
        (CKShare.ParticipantAcceptanceStatus.unknown, SlateShareAcceptance.unknown),
        (CKShare.ParticipantAcceptanceStatus.pending, SlateShareAcceptance.pending),
        (CKShare.ParticipantAcceptanceStatus.accepted, SlateShareAcceptance.accepted),
        (CKShare.ParticipantAcceptanceStatus.removed, SlateShareAcceptance.removed),
    ])
    func mapsKnownCloudKitAcceptanceStatuses(
        cloudKitAcceptanceStatus: CKShare.ParticipantAcceptanceStatus,
        slateAcceptance: SlateShareAcceptance
    ) {
        #expect(SlateShareAcceptance(cloudKitAcceptanceStatus: cloudKitAcceptanceStatus) == slateAcceptance)
    }

    @Test
    func mapsUnknownCloudKitStatesToUnknown() throws {
        let futurePermission = try #require(CKShare.ParticipantPermission(rawValue: 999))
        let futureRole = try #require(CKShare.ParticipantRole(rawValue: 999))
        let futureAcceptanceStatus = try #require(CKShare.ParticipantAcceptanceStatus(rawValue: 999))

        #expect(SlateSharePermission(cloudKitPermission: futurePermission) == .unknown)
        #expect(SlateShareRole(cloudKitRole: futureRole) == .unknown)
        #expect(SlateShareAcceptance(cloudKitAcceptanceStatus: futureAcceptanceStatus) == .unknown)
    }

    @Test
    func shareAndParticipantCanBeCapturedBySendableClosure() throws {
        let participant = SlateParticipant(
            displayName: nil,
            role: .administrator,
            permission: .readWrite,
            acceptanceStatus: .accepted
        )
        let share = SlateShare(
            url: URL(string: "https://example.com/admin-share")!,
            title: nil,
            owner: participant,
            participants: [participant],
            currentUserPermission: .readWrite
        )

        let capture: @Sendable () -> SlateShare = {
            #expect(participant.role == .administrator)
            return share
        }

        #expect(capture() == share)
    }
}
