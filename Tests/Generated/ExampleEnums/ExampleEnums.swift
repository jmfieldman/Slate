//
//  ExampleEnums.swift
//  Copyright © 2025 Jason Fieldman.
//

import Foundation

public enum IntegerEnumExample: Int, Sendable {
    case zero = 0
    case one = 1
    case two = 2
}

public enum StringEnumExample: String, Sendable {
    case hello
    case world
}

public enum StringExplicitEnumExample: String, Sendable {
    case value1 = "VAL1"
    case value2 = "VAL2"
}
