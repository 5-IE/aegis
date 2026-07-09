import CoreLocation
import Combine

class BackgroundLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiService: ApiServiceProtocol = ApiService()
    
    // The lock prevents multiple tasks from running at the same time
    private var isSending = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isSending, let location = locations.last else { return }

        isSending = true
        
        Task {
            defer {
                isSending = false
            }
            
            do {
                try await apiService.sendLocation(
                    roomId: 1,
                    positionX: location.coordinate.latitude, // Replace with your trilateration
                    positionY: location.coordinate.longitude,
                    batteryLevel: 74
                )
                
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                
            } catch {
                print("Failed to send location: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }
}
