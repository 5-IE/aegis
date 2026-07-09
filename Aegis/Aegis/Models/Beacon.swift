//
//  File.swift
//  Aegis
//
//  Created by Steve Agustinus on 06/07/26.
//

import Foundation

struct Beacon: Codable {
    let beaconIdentifier: String
    let roomId: Int
    let positionX: Double?
    let positionY: Double?
    
    enum CodingKeys: String, CodingKey {
        case beaconIdentifier = "beacon_identifier"
        case roomId = "room_id"
        case positionX = "position_x"
        case positionY = "position_y"
    }
}
