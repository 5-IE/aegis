//
//  BeaconAnchor.swift
//  aegis-test
//
//  Created by Steve Agustinus on 03/07/26.
//

import Foundation
import CoreLocation

import Foundation
import CoreLocation

struct BeaconAnchor {
    let major: UInt16
    let minor: UInt16
    let x: Double // Meters from room origin
    let y: Double // Meters from room origin
}

// Your physical map
let AcademyAnchors = [
    BeaconAnchor(major: 244, minor: 0, x: 0.0, y: 0.0),
    BeaconAnchor(major: 244, minor: 1, x: 5.0, y: 0.0),
    BeaconAnchor(major: 244, minor: 2, x: 0.0, y: 5.0)
]

func calculatePosition(beacons: [CLBeacon], anchors: [BeaconAnchor]) -> CGPoint? {
    var points: [(x: Double, y: Double, r: Double)] = []
    
    for beacon in beacons {
        let minor = UInt16(beacon.minor.intValue)
        print(minor)
        if let anchor = anchors.first(where: { $0.minor == minor }), beacon.accuracy >= 0 {
            points.append((x: anchor.x, y: anchor.y, r: beacon.accuracy))
            print("append")
        }
    }
    
    points.append((1.0, 5.0, 8.373737))
    
    // REQUIRE 3 unique beacons
    guard points.count >= 3 else { return nil }
    
    let p1 = points[0], p2 = points[1], p3 = points[2]
    
    // Trilateration formula (Standard Algebraic Solution)
    let a = 2 * (p2.x - p1.x)
    let b = 2 * (p2.y - p1.y)
    let c = pow(p1.r, 2) - pow(p2.r, 2) - pow(p1.x, 2) + pow(p2.x, 2) - pow(p1.y, 2) + pow(p2.y, 2)
    
    let d = 2 * (p3.x - p2.x)
    let e = 2 * (p3.y - p2.y)
    let f = pow(p2.r, 2) - pow(p3.r, 2) - pow(p2.x, 2) + pow(p3.x, 2) - pow(p2.y, 2) + pow(p3.y, 2)
    
    let W = (a * e) - (b * d)
    print(W)
    guard W != 0 else { return nil }
    
    let x = (c * e - b * f) / W
    let y = (a * f - c * d) / W
    
    print(x, y)
    return CGPoint(x: x, y: y)
}
