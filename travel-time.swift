import Foundation
import CoreLocation
import MapKit

class TravelTimeCalculator: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let destinationAddress: String
    var currentLocation: CLLocation?
    var didFinish = false

    init(destination: String) {
        self.destinationAddress = destination
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        locationManager.startUpdatingLocation()

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !self.didFinish {
                self.fail("Timed out waiting for location services")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, !didFinish else { return }
        // Skip stale locations
        guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        currentLocation = location
        locationManager.stopUpdatingLocation()
        calculateRoute(from: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !didFinish {
            fail("Location error: \(error.localizedDescription)")
        }
    }

    func calculateRoute(from source: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(destinationAddress) { placemarks, error in
            if let error = error {
                self.fail("Geocoding error: \(error.localizedDescription)")
                return
            }
            guard let placemark = placemarks?.first, let destLocation = placemark.location else {
                self.fail("Could not find location for address: \(self.destinationAddress)")
                return
            }

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destLocation.coordinate))
            request.transportType = .automobile

            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let error = error {
                    self.fail("Directions error: \(error.localizedDescription)")
                    return
                }
                guard let route = response?.routes.first else {
                    self.fail("No route found")
                    return
                }

                let travelMinutes = Int(ceil(route.expectedTravelTime / 60.0))
                let result: [String: Any] = [
                    "travel_minutes": travelMinutes,
                    "current_lat": round(source.coordinate.latitude * 1000000) / 1000000,
                    "current_lon": round(source.coordinate.longitude * 1000000) / 1000000
                ]

                if let jsonData = try? JSONSerialization.data(withJSONObject: result),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                    self.finish(code: 0)
                } else {
                    self.fail("Failed to serialize JSON")
                }
            }
        }
    }

    func fail(_ message: String) {
        didFinish = true
        fputs("Error: \(message)\n", stderr)
        finish(code: 1)
    }

    func finish(code: Int32) {
        didFinish = true
        exit(code)
    }
}

// MARK: - Main

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: travel-time <destination address>\n", stderr)
    exit(1)
}

let destination = CommandLine.arguments[1]
let calculator = TravelTimeCalculator(destination: destination)
calculator.start()

RunLoop.main.run()
