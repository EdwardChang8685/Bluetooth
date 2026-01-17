//
//  Item.swift
//  Bluetooth
//
//  Created by Edward Chang on 2026/01/17.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
