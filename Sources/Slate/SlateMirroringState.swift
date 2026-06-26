@preconcurrency import CloudKit
import Foundation
import Observation

public enum SlateAccountStatus: Sendable, Equatable {
    case available
    case unavailable
    case restricted
    case couldNotDetermine

    init(cloudKitStatus: CKAccountStatus) {
        switch cloudKitStatus {
        case .available:
            self = .available
        case .noAccount, .temporarilyUnavailable:
            self = .unavailable
        case .restricted:
            self = .restricted
        case .couldNotDetermine:
            self = .couldNotDetermine
        @unknown default:
            self = .couldNotDetermine
        }
    }
}

@Observable
public final class SlateMirroringState {
    public private(set) var accountStatus: SlateAccountStatus
    public private(set) var isImporting: Bool
    public private(set) var isMerging: Bool
    public private(set) var lastImportError: Error?

    public init() {
        self.accountStatus = .unavailable
        self.isImporting = false
        self.isMerging = false
        self.lastImportError = nil
    }

    @MainActor
    func updateAccountStatus(_ status: SlateAccountStatus) {
        accountStatus = status
    }

    @MainActor
    func updateImportState(isImporting: Bool, error: Error?) {
        self.isImporting = isImporting
        if let error {
            lastImportError = error
        }
    }

    @MainActor
    func updateIsMerging(_ isMerging: Bool) {
        self.isMerging = isMerging
    }
}
