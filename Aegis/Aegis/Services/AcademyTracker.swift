import Foundation
import CoreLocation
import Combine
import UIKit

class AcademyTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiService: ApiServiceProtocol = ApiService()
    
    @Published var currentPosition: CGPoint = .zero
    
    // State management
    private var beaconDistances: [UInt16: Double] = [:]
    private var isSending = false
    
    // Beacon Configuration
    private let targetUUID = UUID(uuidString: "26D0814C-F81C-4B2D-AC57-032E2AFF8642")!
    private let anchors = [
        BeaconAnchor(major: 244, minor: 0, x: 0.0, y: 0.0),
        BeaconAnchor(major: 244, minor: 1, x: 5.0, y: 5.0),
        BeaconAnchor(major: 244, minor: 2, x: 10.0, y: 0.0)
    ]
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.requestAlwaysAuthorization()
        
        let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
        locationManager.startRangingBeacons(satisfying: constraint)
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        // 1. Update our cache of distances
        for beacon in beacons where beacon.accuracy >= 0 {
            let minor = UInt16(beacon.minor.intValue)
            beaconDistances[minor] = beacon.accuracy
        }
        
        // 2. Try to calculate position
        if let newPosition = performTrilateration() {
            self.currentPosition = newPosition
            
            // 3. Rate-limited network transmission
            if !isSending {
                sendLocationToServer(x: newPosition.x, y: newPosition.y)
            }
        }
    }
    
    private func performTrilateration() -> CGPoint? {
        // Ensure we have distances for minor 0, 1, and 2
        guard let r0 = beaconDistances[0], let r1 = beaconDistances[1], let r2 = beaconDistances[2] else {
            return nil
        }
        
        // Use the anchors corresponding to minors 0, 1, 2
        let p1 = (x: 0.0, y: 0.0, r: r0)
        let p2 = (x: 5.0, y: 0.0, r: r1)
        let p3 = (x: 0.0, y: 5.0, r: r2)
        
        // Trilateration math
        let a = 2 * (p2.x - p1.x), b = 2 * (p2.y - p1.y)
        let c = pow(p1.r, 2) - pow(p2.r, 2) - pow(p1.x, 2) + pow(p2.x, 2) - pow(p1.y, 2) + pow(p2.y, 2)
        let d = 2 * (p3.x - p2.x), e = 2 * (p3.y - p2.y)
        let f = pow(p2.r, 2) - pow(p3.r, 2) - pow(p2.x, 2) + pow(p3.x, 2) - pow(p2.y, 2) + pow(p3.y, 2)
        
        let W = (a * e) - (b * d)
        guard W != 0 else { return nil }
        
        print(CGPoint(x: (c * e - b * f) / W, y: (a * f - c * d) / W))
        return CGPoint(x: (c * e - b * f) / W, y: (a * f - c * d) / W)
    }

    private func sendLocationToServer(x: CGFloat, y: CGFloat) {
        isSending = true
        Task {
            defer {
                Task {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    isSending = false
                }
            }
            
            try? await apiService.sendLocation(
                roomId: 1,
                positionX: (x * 100).rounded() / 100,
                positionY: (y * 100).rounded() / 100,
                batteryLevel: abs(Int(UIDevice.current.batteryLevel * 100))
            )
        }
    }
}
