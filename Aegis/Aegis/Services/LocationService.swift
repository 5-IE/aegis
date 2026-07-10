import Foundation
import CoreLocation
import Combine
import UIKit

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let dataStore: DataStore
    
    @Published var currentPosition: CGPoint = .zero
    
    // State management
    private var beaconDistances: [Int: Double] = [:]
    private var isSending = false
    
    // Beacon Configuration
    private let targetUUID = UUID(uuidString: "26D0814C-F81C-4B2D-AC57-032E2AFF8642")!
    private var anchors: [Beacon] = []
    
    init(dataStore: DataStore) {
        self.dataStore = dataStore
        super.init()
        setupLocationManager()
        Task {
            await self.fetchBeacons(store: dataStore)
        }
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
    
    func fetchBeacons(store: DataStore) async {
        do {
            let response = try await store.fetchBeacons()
            let beaconsData = response.list
            
            self.anchors = beaconsData.map { Beacon(from: $0) }
            
        } catch let error as URLError where error.code == .cancelled {
            // Silently ignore cancellation errors
            print("Request was cancelled - this is expected behavior.")
        } catch let error as ApiError {
            print("\(error.error ?? "Error") - \(error.message ?? "Something went wrong")")
        } catch {
            print("An unexpected error occurred.")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        // 1. Update our cache of distances
        for beacon in beacons where beacon.accuracy >= 0 {
            let minor = Int(beacon.minor.intValue)
            beaconDistances[minor] = beacon.accuracy
        }
        
        processBeaconData()
    }
    
    private func processBeaconData() {
        // Prevent processing if we are currently rate-limiting the network
        guard !isSending else { return }
        
        // 1. Find the closest beacon from our active distances
        guard let closestMinor = beaconDistances.min(by: { $0.value < $1.value })?.key,
              let closestBeaconNode = anchors.first(where: { $0.minor == closestMinor }) else {
            return
        }
        
        let targetRoomId = closestBeaconNode.roomId
        
        // 2. Find all beacons that belong to this room AND have a current distance reading
        let activeBeaconsInRoom = anchors
            .filter { $0.roomId == targetRoomId }
            .compactMap { beacon -> (beacon: Beacon, distance: Double)? in
                guard let distance = beaconDistances[beacon.minor] else { return nil }
                return (beacon, distance)
            }
            .sorted { $0.distance < $1.distance } // Sort from closest to furthest
        
        // 3. Route based on how many beacons are visible in the room
        if activeBeaconsInRoom.count >= 3 {
            // We have at least 3. Grab the closest 3 for the math.
            let top3 = Array(activeBeaconsInRoom.prefix(3))
            
            if let position = performTrilateration(with: top3) {
                self.currentPosition = position
                sendLocationToServer(roomId: targetRoomId, x: position.x, y: position.y)
            }
        } else if activeBeaconsInRoom.count > 0 {
            // Only 1 or 2 beacons visible in this room
            sendLocationToServer(roomId: targetRoomId, x: 0, y: 0)
        }
    }
    
    private func performTrilateration(with data: [(beacon: Beacon, distance: Double)]) -> CGPoint? {
        guard data.count == 3,
              let x1 = data[0].beacon.x, let y1 = data[0].beacon.y,
              let x2 = data[1].beacon.x, let y2 = data[1].beacon.y,
              let x3 = data[2].beacon.x, let y3 = data[2].beacon.y else {
            return nil
        }
        
        let p1 = (x: x1, y: y1, r: data[0].distance)
        let p2 = (x: x2, y: y2, r: data[1].distance)
        let p3 = (x: x3, y: y3, r: data[2].distance)
        
        // Trilateration math
        let a = 2 * (p2.x - p1.x), b = 2 * (p2.y - p1.y)
        let c = pow(p1.r, 2) - pow(p2.r, 2) - pow(p1.x, 2) + pow(p2.x, 2) - pow(p1.y, 2) + pow(p2.y, 2)
        let d = 2 * (p3.x - p2.x), e = 2 * (p3.y - p2.y)
        let f = pow(p2.r, 2) - pow(p3.r, 2) - pow(p2.x, 2) + pow(p3.x, 2) - pow(p2.y, 2) + pow(p3.y, 2)
        
        let W = (a * e) - (b * d)
        guard W != 0 else { return nil }
        
        return CGPoint(x: (c * e - b * f) / W, y: (a * f - c * d) / W)
    }

    private func sendLocationToServer(roomId: Int, x: CGFloat, y: CGFloat) {
        isSending = true
        Task {
            defer {
                Task {
                    try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                    isSending = false
                }
            }
            
            do {
                _ = try await dataStore.sendPresence(
                    roomId: roomId,
                    positionX: (x * 100).rounded() / 100,
                    positionY: (y * 100).rounded() / 100,
                    batteryLevel: abs(Int(UIDevice.current.batteryLevel * 100))
                )
            } catch let error as ApiError {
                print(error)
            } catch {
                print("Failed to send location: \(error.localizedDescription)")
            }
        }
    }
}
