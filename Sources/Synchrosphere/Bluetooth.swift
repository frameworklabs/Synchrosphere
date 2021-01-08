// Project Synchrosphere
// Copyright 2021, Framework Labs.

import CoreBluetooth

extension CBUUID {
    
    // MARK: Services
    
    static let spheroService = CBUUID(string: "00010001-574f-4f20-5370-6865726f2121")

    // MARK: Characteristics
    
    static let apiCharacteristic = CBUUID(string: "00010002-574f-4f20-5370-6865726f2121")
    static let antiDoSCharacteristic = CBUUID(string: "00020005-574f-4f20-5370-6865726f2121")
}
