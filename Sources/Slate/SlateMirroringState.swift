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
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var storedAccountStatus: SlateAccountStatus
    @ObservationIgnored private var storedIsImporting: Bool
    @ObservationIgnored private var storedIsMerging: Bool
    @ObservationIgnored private var storedLastImportError: Error?

    public init() {
        self.storedAccountStatus = .unavailable
        self.storedIsImporting = false
        self.storedIsMerging = false
        self.storedLastImportError = nil
    }

    public private(set) var accountStatus: SlateAccountStatus {
        get {
            access(keyPath: \.accountStatus)
            lock.lock()
            defer { lock.unlock() }
            return storedAccountStatus
        }
        set {
            withMutation(keyPath: \.accountStatus) {
                lock.lock()
                storedAccountStatus = newValue
                lock.unlock()
            }
        }
    }

    public private(set) var isImporting: Bool {
        get {
            access(keyPath: \.isImporting)
            lock.lock()
            defer { lock.unlock() }
            return storedIsImporting
        }
        set {
            withMutation(keyPath: \.isImporting) {
                lock.lock()
                storedIsImporting = newValue
                lock.unlock()
            }
        }
    }

    public private(set) var isMerging: Bool {
        get {
            access(keyPath: \.isMerging)
            lock.lock()
            defer { lock.unlock() }
            return storedIsMerging
        }
        set {
            withMutation(keyPath: \.isMerging) {
                lock.lock()
                storedIsMerging = newValue
                lock.unlock()
            }
        }
    }

    public private(set) var lastImportError: Error? {
        get {
            access(keyPath: \.lastImportError)
            lock.lock()
            defer { lock.unlock() }
            return storedLastImportError
        }
        set {
            withMutation(keyPath: \.lastImportError) {
                lock.lock()
                storedLastImportError = newValue
                lock.unlock()
            }
        }
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
