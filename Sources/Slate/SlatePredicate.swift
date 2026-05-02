import Foundation
import SlateSchema

public struct SlatePredicate<Root>: Sendable {
    let expression: SlatePredicateExpression

    public init(_ expression: SlatePredicateExpression) {
        self.expression = expression
    }

    public static func predicate(_ predicate: NSPredicate) -> Self {
        Self(.raw(SendablePredicate(predicate)))
    }

    public static func `in`<Value: Sendable>(_ keyPath: KeyPath<Root, Value>, _ values: some Collection<Value>) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .in, value: SendableValue(Array(values))))
    }

    public static func notIn<Value: Sendable>(_ keyPath: KeyPath<Root, Value>, _ values: some Collection<Value>) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .notIn, value: SendableValue(Array(values))))
    }

    public static func isNil<Value>(_ keyPath: KeyPath<Root, Value?>) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .isNil, value: nil))
    }

    public static func isNotNil<Value>(_ keyPath: KeyPath<Root, Value?>) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .isNotNil, value: nil))
    }

    public static func contains(_ keyPath: KeyPath<Root, String>, _ value: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .contains(options), value: SendableValue(value)))
    }

    public static func contains(_ keyPath: KeyPath<Root, String?>, _ value: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .contains(options), value: SendableValue(value)))
    }

    public static func beginsWith(_ keyPath: KeyPath<Root, String>, _ value: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .beginsWith(options), value: SendableValue(value)))
    }

    public static func beginsWith(_ keyPath: KeyPath<Root, String?>, _ value: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .beginsWith(options), value: SendableValue(value)))
    }

    public static func endsWith(_ keyPath: KeyPath<Root, String>, _ value: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .endsWith(options), value: SendableValue(value)))
    }

    public static func endsWith(_ keyPath: KeyPath<Root, String?>, _ value: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .endsWith(options), value: SendableValue(value)))
    }

    public static func matches(_ keyPath: KeyPath<Root, String>, _ pattern: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .matches(options), value: SendableValue(pattern)))
    }

    public static func matches(_ keyPath: KeyPath<Root, String?>, _ pattern: String, options: SlateStringOptions = []) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .matches(options), value: SendableValue(pattern)))
    }

    public static func between<Value: Comparable & Sendable>(_ keyPath: KeyPath<Root, Value>, _ range: ClosedRange<Value>) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .between, value: SendableValue([range.lowerBound, range.upperBound])))
    }

    public static func between<Value: Comparable & Sendable>(_ keyPath: KeyPath<Root, Value?>, _ range: ClosedRange<Value>) -> Self where Root: SlateKeypathAttributeProviding {
        Self(.comparison(attribute: Root.keypathToAttribute(keyPath), op: .between, value: SendableValue([range.lowerBound, range.upperBound])))
    }
}

public struct SlateStringOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let caseInsensitive = SlateStringOptions(rawValue: 1 << 0)
    public static let diacriticInsensitive = SlateStringOptions(rawValue: 1 << 1)

    var nsPredicateModifiers: String {
        guard !isEmpty else { return "" }
        var s = "["
        if contains(.caseInsensitive) { s += "c" }
        if contains(.diacriticInsensitive) { s += "d" }
        s += "]"
        return s
    }
}

public indirect enum SlatePredicateExpression: Sendable {
    case comparison(attribute: String, op: SlateComparisonOperator, value: SendableValue)
    case and(SlatePredicateExpression, SlatePredicateExpression)
    case or(SlatePredicateExpression, SlatePredicateExpression)
    case not(SlatePredicateExpression)
    case raw(SendablePredicate)

    var nsPredicate: NSPredicate {
        switch self {
        case let .comparison(attribute, op, value):
            op.predicate(attribute: attribute, value: value.value)
        case let .and(lhs, rhs):
            NSCompoundPredicate(andPredicateWithSubpredicates: [lhs.nsPredicate, rhs.nsPredicate])
        case let .or(lhs, rhs):
            NSCompoundPredicate(orPredicateWithSubpredicates: [lhs.nsPredicate, rhs.nsPredicate])
        case let .not(expression):
            NSCompoundPredicate(notPredicateWithSubpredicate: expression.nsPredicate)
        case let .raw(predicate):
            predicate.value
        }
    }
}

public enum SlateComparisonOperator: Sendable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case `in`
    case notIn
    case isNil
    case isNotNil
    case contains(SlateStringOptions)
    case beginsWith(SlateStringOptions)
    case endsWith(SlateStringOptions)
    case matches(SlateStringOptions)
    case between

    func predicate(attribute: String, value: Any?) -> NSPredicate {
        switch self {
        case .equal:
            return NSPredicate(format: "%K == %@", argumentArray: [attribute, argument(value)])
        case .notEqual:
            return NSPredicate(format: "%K != %@", argumentArray: [attribute, argument(value)])
        case .lessThan:
            return NSPredicate(format: "%K < %@", argumentArray: [attribute, argument(value)])
        case .lessThanOrEqual:
            return NSPredicate(format: "%K <= %@", argumentArray: [attribute, argument(value)])
        case .greaterThan:
            return NSPredicate(format: "%K > %@", argumentArray: [attribute, argument(value)])
        case .greaterThanOrEqual:
            return NSPredicate(format: "%K >= %@", argumentArray: [attribute, argument(value)])
        case .in:
            return NSPredicate(format: "%K IN %@", argumentArray: [attribute, argument(value)])
        case .notIn:
            return NSPredicate(format: "NOT (%K IN %@)", argumentArray: [attribute, argument(value)])
        case .isNil:
            return NSPredicate(format: "%K == nil", argumentArray: [attribute])
        case .isNotNil:
            return NSPredicate(format: "%K != nil", argumentArray: [attribute])
        case let .contains(options):
            return NSPredicate(format: "%K CONTAINS\(options.nsPredicateModifiers) %@", argumentArray: [attribute, argument(value)])
        case let .beginsWith(options):
            return NSPredicate(format: "%K BEGINSWITH\(options.nsPredicateModifiers) %@", argumentArray: [attribute, argument(value)])
        case let .endsWith(options):
            return NSPredicate(format: "%K ENDSWITH\(options.nsPredicateModifiers) %@", argumentArray: [attribute, argument(value)])
        case let .matches(options):
            return NSPredicate(format: "%K MATCHES\(options.nsPredicateModifiers) %@", argumentArray: [attribute, argument(value)])
        case .between:
            return NSPredicate(format: "%K BETWEEN %@", argumentArray: [attribute, argument(value)])
        }
    }

    private func argument(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        return Self.unwrapRawRepresentable(value)
    }

    /// Recursively unwrap `RawRepresentable` values so that comparisons
    /// against persisted enum attributes use the stored raw value
    /// (`String`, `Int16`, `Int32`, or `Int64`). Arrays and sets are
    /// projected element-by-element so that `IN`/`NOT IN`/`BETWEEN`
    /// predicates also see raw values.
    static func unwrapRawRepresentable(_ value: Any) -> Any {
        if let collection = value as? [Any] {
            return collection.map { Self.unwrapRawRepresentable($0) }
        }
        if let raw = (value as? any RawRepresentable)?.rawValue {
            return raw
        }
        return value
    }
}

/// Carrier for an `NSPredicate` reference passed through `SlatePredicate.predicate(_:)`.
///
/// Why `@unchecked Sendable`: `NSPredicate` is an `NSObject` subclass, so it
/// does not auto-conform to `Sendable` even though Apple documents predicates
/// constructed with format strings as immutable and safe to share between
/// threads. Slate only ever stores the original reference and reads its
/// `predicateFormat` / `evaluate(...)` from the writer or reader queues; we
/// never mutate it after construction. Callers that hand-build a mutable
/// `NSMutablePredicate` and then mutate it after handing it to Slate are
/// outside the supported surface.
public struct SendablePredicate: @unchecked Sendable {
    let value: NSPredicate

    public init(_ value: NSPredicate) {
        self.value = value
    }
}

/// Carrier for the right-hand side of a Slate predicate comparison.
///
/// Storage is `(any Sendable)?` so the struct is naturally `Sendable` —
/// callers must hand in `Sendable` values via `init<T: Sendable>`. Predicate
/// helpers and operators in this file thread `Value: Sendable` constraints
/// through, so the on-disk attribute types Slate supports (`String`, `Int*`,
/// `Double`, `Bool`, `Date`, `UUID`, `URL`, `Data`, `Decimal`, raw-value
/// enums, and arrays of those) all flow through without an unchecked box.
public struct SendableValue: Sendable, ExpressibleByNilLiteral {
    let value: (any Sendable)?

    public init<T: Sendable>(_ value: T?) {
        self.value = value
    }

    public init(nilLiteral: ()) {
        self.value = nil
    }
}

public func && <Root>(lhs: SlatePredicate<Root>, rhs: SlatePredicate<Root>) -> SlatePredicate<Root> {
    SlatePredicate(.and(lhs.expression, rhs.expression))
}

public func || <Root>(lhs: SlatePredicate<Root>, rhs: SlatePredicate<Root>) -> SlatePredicate<Root> {
    SlatePredicate(.or(lhs.expression, rhs.expression))
}

public prefix func ! <Root>(predicate: SlatePredicate<Root>) -> SlatePredicate<Root> {
    SlatePredicate(.not(predicate.expression))
}

public func == <Root, Value: Sendable>(lhs: KeyPath<Root, Value>, rhs: Value) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .equal, value: SendableValue(rhs)))
}

public func != <Root, Value: Sendable>(lhs: KeyPath<Root, Value>, rhs: Value) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .notEqual, value: SendableValue(rhs)))
}

public func == <Root, Value: Sendable>(lhs: KeyPath<Root, Value?>, rhs: Value?) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    if let rhs {
        return SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .equal, value: SendableValue(rhs)))
    }
    return SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .isNil, value: nil))
}

public func != <Root, Value: Sendable>(lhs: KeyPath<Root, Value?>, rhs: Value?) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    if let rhs {
        return SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .notEqual, value: SendableValue(rhs)))
    }
    return SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .isNotNil, value: nil))
}

public func < <Root, Value: Sendable>(lhs: KeyPath<Root, Value>, rhs: Value) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .lessThan, value: SendableValue(rhs)))
}

public func <= <Root, Value: Sendable>(lhs: KeyPath<Root, Value>, rhs: Value) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .lessThanOrEqual, value: SendableValue(rhs)))
}

public func > <Root, Value: Sendable>(lhs: KeyPath<Root, Value>, rhs: Value) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .greaterThan, value: SendableValue(rhs)))
}

public func >= <Root, Value: Sendable>(lhs: KeyPath<Root, Value>, rhs: Value) -> SlatePredicate<Root> where Root: SlateKeypathAttributeProviding {
    SlatePredicate(.comparison(attribute: Root.keypathToAttribute(lhs), op: .greaterThanOrEqual, value: SendableValue(rhs)))
}

public struct SlateSort<Root>: Sendable {
    let attribute: String
    let ascending: Bool

    public init(_ keyPath: PartialKeyPath<Root>, ascending: Bool = true) where Root: SlateKeypathAttributeProviding {
        self.attribute = Root.keypathToAttribute(keyPath)
        self.ascending = ascending
    }

    public init(attribute: String, ascending: Bool = true) {
        self.attribute = attribute
        self.ascending = ascending
    }

    /// Ascending sort by `keyPath`. Lets callers write
    /// `sort: [.asc(\.lastName), .desc(\.createdAt)]` when the element
    /// type is already inferred (e.g., from `slate.many(Patient.self, ...)`).
    public static func asc(_ keyPath: PartialKeyPath<Root>) -> SlateSort<Root> where Root: SlateKeypathAttributeProviding {
        SlateSort(keyPath, ascending: true)
    }

    /// Descending sort by `keyPath`.
    public static func desc(_ keyPath: PartialKeyPath<Root>) -> SlateSort<Root> where Root: SlateKeypathAttributeProviding {
        SlateSort(keyPath, ascending: false)
    }

    var descriptor: NSSortDescriptor {
        NSSortDescriptor(key: attribute, ascending: ascending)
    }
}
