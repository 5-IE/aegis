//
//  File.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//

import Foundation

struct Beacon {
    let major: Int
    let minor: Int
    let roomId: Int
    let x: Double?
    let y: Double?
}

extension Beacon {
    init(from apiModel: BeaconData) {
        let components = apiModel.beaconIdentifier.components(separatedBy: ":")
        
        let major = Int(components.first ?? "0") ?? 0
        let minor = Int(components.last ?? "0") ?? 0
        
        self.major = major
        self.minor = minor
        self.roomId = apiModel.roomId
        self.x = apiModel.positionX
        self.y = apiModel.positionY
    }
}
