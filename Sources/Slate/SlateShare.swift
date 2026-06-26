@preconcurrency import CloudKit
import Foundation

public struct SlateShare: Sendable, Equatable {
    public let url: URL?
    public let title: String?
    public let owner: SlateParticipant
    public let participants: [SlateParticipant]
    public let currentUserPermission: SlateSharePermission

    public init(
        url: URL?,
        title: String?,
        owner: SlateParticipant,
        participants: [SlateParticipant],
        currentUserPermission: SlateSharePermission
    ) {
        self.url = url
        self.title = title
        self.owner = owner
        self.participants = participants
        self.currentUserPermission = currentUserPermission
    }
}

public struct SlateParticipant: Sendable, Equatable {
    public let displayName: String?
    public let role: SlateShareRole
    public let permission: SlateSharePermission
    public let acceptanceStatus: SlateShareAcceptance

    public init(
        displayName: String?,
        role: SlateShareRole,
        permission: SlateSharePermission,
        acceptanceStatus: SlateShareAcceptance
    ) {
        self.displayName = displayName
        self.role = role
        self.permission = permission
        self.acceptanceStatus = acceptanceStatus
    }
}

public enum SlateSharePermission: Sendable, Equatable {
    case unknown
    case none
    case readOnly
    case readWrite

    init(cloudKitPermission: CKShare.ParticipantPermission) {
        switch cloudKitPermission {
        case .unknown:
            self = .unknown
        case .none:
            self = .none
        case .readOnly:
            self = .readOnly
        case .readWrite:
            self = .readWrite
        @unknown default:
            self = .unknown
        }
    }
}

public enum SlateShareRole: Sendable, Equatable {
    case unknown
    case owner
    case privateUser
    case publicUser
    case administrator

    init(cloudKitRole: CKShare.ParticipantRole) {
        switch cloudKitRole {
        case .unknown:
            self = .unknown
        case .owner:
            self = .owner
        case .privateUser:
            self = .privateUser
        case .publicUser:
            self = .publicUser
        case .administrator:
            self = .administrator
        @unknown default:
            self = .unknown
        }
    }
}

public enum SlateShareAcceptance: Sendable, Equatable {
    case unknown
    case pending
    case accepted
    case removed

    init(cloudKitAcceptanceStatus: CKShare.ParticipantAcceptanceStatus) {
        switch cloudKitAcceptanceStatus {
        case .unknown:
            self = .unknown
        case .pending:
            self = .pending
        case .accepted:
            self = .accepted
        case .removed:
            self = .removed
        @unknown default:
            self = .unknown
        }
    }
}
