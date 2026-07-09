//
//  BeaconScanner.swift
//  aegis-test
//
//  Created by Steve Agustinus on 01/07/26.
//


import Foundation
import CoreLocation
import Combine
internal import CoreGraphics

class BeaconScanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var detectedBeacons: [CLBeacon] = []
    @Published var authStatusString: String = "Initializing..."
    @Published var errorMessage: String? = nil
    
    // Exact matching UUID from your ESP32 NimBLE setup
    let targetUUIDString = "26D0814C-F81C-4B2D-AC57-032E2AFF8642"
    
    @Published var currentPosition: CGPoint = .zero
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true // Required for transparency
        
        // Start standard location updates (or just beacon monitoring)
        locationManager.startUpdatingLocation()
        
        // Update initial status display
        updateAuthStatus(locationManager.authorizationStatus)
    }
    
    func requestPermission() {
        print("Requesting Location Permission...")
        // Requesting "When In Use" first is the most reliable way to get the prompt to appear
        locationManager.requestWhenInUseAuthorization()
    }
    
    // Fires automatically whenever permission status changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthStatus(manager.authorizationStatus)
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Permission granted. Checking capabilities...")
            if CLLocationManager.isRangingAvailable() {
                startRanging()
            } else {
                self.errorMessage = "Device does not support BLE ranging."
            }
        case .denied, .restricted:
            self.errorMessage = "Location access denied/restricted. Enable it in iOS Settings."
        case .notDetermined:
            self.errorMessage = "Permission not determined yet."
        @unknown default:
            break
        }
    }
    
    private func updateAuthStatus(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            switch status {
            case .notDetermined: self.authStatusString = "Not Determined (Needs Prompt)"
            case .restricted: self.authStatusString = "Restricted"
            case .denied: self.authStatusString = "Denied"
            case .authorizedAlways: self.authStatusString = "Authorized Always"
            case .authorizedWhenInUse: self.authStatusString = "Authorized When In Use"
            @unknown default: self.authStatusString = "Unknown"
            }
        }
    }
    
    private func startRanging() {
        guard let uuid = UUID(uuidString: targetUUIDString) else {
            self.errorMessage = "Invalid UUID String format."
            return
        }
        
        print("Starting monitoring and ranging for UUID: \(targetUUIDString)")
        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
        let region = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: "AcademyBeaconRegion")
        
        // Start both components to ensure iOS registers the geofence
        locationManager.startMonitoring(for: region)
        locationManager.startRangingBeacons(satisfying: constraint)
        
        self.errorMessage = nil
    }
    
    // Core callback where data actually arrives
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        DispatchQueue.main.async {
            // Filter out unknown distances to keep the data clean
            self.detectedBeacons = beacons
//            print("Ranged \(beacons.count) beacons.")
            if let newPosition = calculatePosition(beacons: beacons, anchors: AcademyAnchors) {
                self.currentPosition = newPosition
                print("Calculated Position: \(newPosition)")
            }
        }
    }
    
    // --- DIAGNOSTIC ERROR CATCHERS ---
    func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Ranging Failed: \(error.localizedDescription)"
            print("[ERROR] Ranging failed: \(error)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Location Error: \(error.localizedDescription)"
            print("[ERROR] General location failure: \(error)")
        }
    }
}
