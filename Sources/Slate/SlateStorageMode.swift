public enum SlateStorageMode: Sendable, Equatable {
    case local
    case cloudKitMirrored(containerIdentifier: String)
    case cloudKitShared(containerIdentifier: String)
}

extension SlateStorageMode {
    var isCloudKit: Bool {
        switch self {
        case .local:
            return false
        case .cloudKitMirrored, .cloudKitShared:
            return true
        }
    }
}
