//
//  String+ReplaceMap.swift
//  slate
//
//  Created by Jason Fieldman on 5/29/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
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
