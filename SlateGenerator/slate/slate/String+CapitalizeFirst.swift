//
//  String+CapitalizeFirst.swift
//  slate
//
//  Created by Kyle Lee on 11/18/19.
//  Copyright © 2019 Jason Fieldman. All rights reserved.
//

import Foundation

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}
