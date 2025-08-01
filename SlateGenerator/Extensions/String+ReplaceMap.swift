//
//  String+ReplaceMap.swift
//  Copyright © 2020 Jason Fieldman.
//

import Foundation

extension String {
    func replacingWithMap(_ replaceMap: [String: String]) -> String {
        var intermediate = self
        for (k, v) in replaceMap {
            intermediate = intermediate.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return intermediate
    }
}
