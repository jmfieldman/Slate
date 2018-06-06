//
//  UpdatableListNode.swift
//  Swift -- Core Data
//
//  Copyright (c) 2018-Present Jason Fieldman - https://github.com/jmfieldman/Slate
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation


// MARK: - UpdatableListNode

/**
 This protocol can be applied to any class/struct that might be used as the
 basis for a view model array.  The code will determine the insert/delete/move
 operations to update a collection view.
 */
public protocol UpdatableListNode {
    
    /**
     Returns the singular equatable element corresponding to the node item that
     can be used to determine if the node is 'similar' to another node from
     the perspective of it occupying the same position in a list from one
     mutation to another.
     */
    var similarityElement: AnyHashable { get }
    
    /**
     Used to determine if an index with similar nodes needs to be reloaded
     */
    func isEqualTo(node: UpdatableListNode) -> Bool
 
}

public class UpdatableList {
    static func updatesNeeded<T: UpdatableListNode>(from oldArray: [T], to newArray: [T]) -> (insert: [Int], delete: [Int], move: [(from: Int, to: Int)], reload: [Int]) {
        var movement: [AnyHashable : (prev: Int, new: Int?)] = [:] /* Tracks prev/new positions for each OID */
        var toInsert: [Int] = []                                   /* Tracks index paths that have new OIDs */
        var toDelete: [Int] = []                                   /* Tracks index paths that have OIDs no longer present */
        var toReload: [Int] = []                                   /* Tracks index paths to reload */
        var toMove: [(Int, Int)] = []                              /* A list of from->to pairs */
        
        // Setup previous indexes
        for i in 0 ..< oldArray.count {
            movement[oldArray[i].similarityElement] = (prev: i, new: nil)
        }
        
        // Setup new indexes
        for i in 0 ..< newArray.count {
            if let m = movement[newArray[i].similarityElement] {
                movement[newArray[i].similarityElement] = (prev: m.prev, new: i)
                if (m.prev != i) {
                    toMove.append((m.prev, i))
                } else if (!oldArray[m.prev].isEqualTo(node: newArray[i])) {
                    toReload.append(i)
                }
            } else {
                toInsert.append(i)
            }
        }
        
        // To delete
        for (_, pos) in movement {
            if (pos.new == nil) {
                toDelete.append(pos.prev)
            }
        }
        
        return (toInsert, toDelete, toMove, toReload)
    }
}

public extension Array where Element == UpdatableListNode {

    
}
