import Foundation

public struct SchemaDumper: Sendable {
    public init() {}

    public func dump(_ schema: NormalizedSchema, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return String(decoding: try encoder.encode(schema), as: UTF8.self)
    }
}
