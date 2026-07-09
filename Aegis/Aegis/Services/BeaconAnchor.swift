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
    BeaconAnchor(major: 244, minor: 0, x: 5.0, y: 0.0),
    BeaconAnchor(major: 244, minor: 0, x: 0.0, y: 5.0)
]

func calculatePosition(beacons: [CLBeacon], anchors: [BeaconAnchor]) -> CGPoint? {
    var points: [(Double, Double, Double)] = []
    
    for beacon in beacons {
        // Safe casting: CLBeaconMajorValue is UInt16
        let major = UInt16(beacon.major.intValue)
        let minor = UInt16(beacon.minor.intValue)
        
        if let anchor = anchors.first(where: { $0.major == major && $0.minor == minor }) {
            // Only include if accuracy is valid (>= 0)
            if beacon.accuracy >= 0 {
                points.append((anchor.x, anchor.y, beacon.accuracy))
                print(points)
            }
        }
    }
    
    guard points.count >= 3 else { return nil }
    
    // 2. Solve the linear system
    // Using the Least Squares approach for trilateration:
    let (p1, p2, p3) = (points[0], points[1], points[2])
    
    let a = 2 * (p2.0 - p1.0)
    let b = 2 * (p2.1 - p1.1)
    let c = pow(p1.2, 2) - pow(p2.2, 2) - pow(p1.0, 2) + pow(p2.0, 2) - pow(p1.2, 2) + pow(p2.1, 2)
    
    let d = 2 * (p3.0 - p2.0)
    let e = 2 * (p3.1 - p2.1)
    let f = pow(p2.2, 2) - pow(p3.2, 2) - pow(p2.0, 2) + pow(p3.0, 2) - pow(p2.1, 2) + pow(p3.1, 2)
    
    let W = (a * e) - (b * d)
    if W == 0 { return nil }
    
    let x = (c * e - b * f) / W
    let y = (a * f - c * d) / W
    
    print(CGPoint(x: x, y: y))
    return CGPoint(x: x, y: y)
}
