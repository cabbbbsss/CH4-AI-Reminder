import Foundation
import CoreLocation
import Observation
import MapKit

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
  static let shared = LocationService()
  private let locationManager = CLLocationManager()
  
  var currentLocationName: String = "Unknown"
  
  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    
    // Continuous tracking (commented out as requested, for battery efficiency)
    // locationManager.startUpdatingLocation()
    
    // Using Region Monitoring and Significant Location Changes instead
    locationManager.startMonitoringSignificantLocationChanges()
  }
  
  func startMonitoring(region: CLCircularRegion) {
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
    locationManager.startMonitoring(for: region)
  }
  
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    
    Task {
      // FIX: Safely unwrap the optional initializer
      guard let request = MKReverseGeocodingRequest(location: location) else {
        print("Failed to initialize MKReverseGeocodingRequest")
        return
      }
      
      do {
        let mapItems = try await request.mapItems
        
        if let firstPlace = mapItems.first {
          await MainActor.run {
            self.currentLocationName = firstPlace.name ?? "Unknown Location"
          }
        }
      } catch {
        print("Geocoding failed with error: \(error.localizedDescription)")
      }
    }
  }

  
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    print("Entered region: \(region.identifier)")
    // In a real app, this would notify the AILearningEngine
  }
  
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    print("Exited region: \(region.identifier)")
  }
}
