import Foundation
import CoreLocation
import MapKit
import AVFoundation
import Combine

// MARK: - NavigationManager
// Singleton-ähnliche, geteilte Instanz zwischen Navigation-Tab und Mix-Tab.
// Einzige Quelle für Location, Route, Sprachansagen.

@MainActor
final class NavigationManager: NSObject, ObservableObject {

    // MARK: - Published: Location
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - Published: Search
    @Published var searchQuery = ""
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false

    // MARK: - Published: Route & Destination
    @Published var selectedDestination: MKMapItem?
    @Published var currentRoute: MKRoute?
    @Published var routeDistance: CLLocationDistance = 0   // Preview
    @Published var routeETA: TimeInterval = 0              // Preview (seconds)

    // MARK: - Published: Active Navigation
    @Published var isNavigating = false
    @Published var isRerouting = false
    @Published var currentStepIndex = 0
    @Published var distanceToNextStep: CLLocationDistance = 0
    @Published var remainingDistance: CLLocationDistance = 0
    @Published var estimatedArrivalTime: Date?
    @Published var currentInstruction = ""
    @Published var maneuverSymbol = "arrow.up"

    // MARK: - Published: Errors
    @Published var errorMessage: String?

    // MARK: - Private
    private let locationManager = CLLocationManager()
    private let synthesizer = AVSpeechSynthesizer()
    private var announcedKeys: Set<String> = []
    private var searchTask: Task<Void, Never>?
    private var rerouteTask: Task<Void, Never>?
    private var offRouteSince: Date?

    // Cached step endpoint coordinates for fast lookup
    private var stepEndpoints: [CLLocationCoordinate2D] = []
    // All route coords for off-route check
    private var routeCoordinates: [CLLocationCoordinate2D] = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 8
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
        configureAudioSession()
    }

    // MARK: - Audio Session (duck music during voice)
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession: \(error.localizedDescription)")
        }
    }

    // MARK: - Location Permission

    func requestPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Standort verweigert. Bitte in Einstellungen aktivieren."
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default: break
        }
    }

    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }

    func stopLocationUpdatesIfIdle() {
        guard !isNavigating else { return }
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Search

    func search(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let loc = userLocation {
                request.region = MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 50_000, longitudinalMeters: 50_000
                )
            }
            do {
                let response = try await MKLocalSearch(request: request).start()
                searchResults = response.mapItems
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
    }

    // MARK: - Route Calculation

    func calculateRoute(to destination: MKMapItem) async {
        guard let userLoc = userLocation else {
            errorMessage = "Kein Standort verfügbar. Bitte Standort aktivieren."
            return
        }
        errorMessage = nil
        selectedDestination = destination

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLoc.coordinate))
        request.destination = destination
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return }
            currentRoute = route
            routeDistance = route.distance
            routeETA = route.expectedTravelTime
            stepEndpoints = extractStepEndpoints(route: route)
            routeCoordinates = extractPolylineCoords(polyline: route.polyline)
            if !route.steps.isEmpty {
                updateInstruction(step: route.steps[0])
            }
        } catch {
            errorMessage = "Route nicht berechnet: \(error.localizedDescription)"
        }
    }

    // MARK: - Start / Stop Navigation

    func startNavigation() {
        guard currentRoute != nil else { return }
        isNavigating = true
        currentStepIndex = 0
        announcedKeys = []
        remainingDistance = currentRoute?.distance ?? 0
        locationManager.startUpdatingLocation()

        if let first = currentRoute?.steps.first {
            announce("Navigation gestartet. " + describeStep(step: first, withDistance: nil))
        }
    }

    func stopNavigation() {
        isNavigating = false
        isRerouting = false
        currentRoute = nil
        routePreviewActive = false
        currentStepIndex = 0
        selectedDestination = nil
        remainingDistance = 0
        estimatedArrivalTime = nil
        currentInstruction = ""
        maneuverSymbol = "arrow.up"
        announcedKeys = []
        offRouteSince = nil
        stepEndpoints = []
        routeCoordinates = []
        synthesizer.stopSpeaking(at: .immediate)
        locationManager.stopUpdatingLocation()
    }

    var routePreviewActive = false

    func showRoutePreview() {
        routePreviewActive = true
    }

    func cancelRoutePreview() {
        routePreviewActive = false
        currentRoute = nil
        selectedDestination = nil
        stepEndpoints = []
        routeCoordinates = []
        routeDistance = 0
        routeETA = 0
    }

    // MARK: - Navigation Progress (called from CLLocationManagerDelegate)

    private func updateProgress(location: CLLocation) {
        guard let route = currentRoute, isNavigating else { return }
        let steps = route.steps
        guard currentStepIndex < steps.count else { return }

        let currentStep = steps[currentStepIndex]

        // Distance to end of current step
        let endCoord = stepEndpoints.indices.contains(currentStepIndex) ? stepEndpoints[currentStepIndex] : nil
        if let end = endCoord {
            let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let dist = location.distance(from: endLoc)
            distanceToNextStep = dist

            // Announce at thresholds
            triggerAnnouncements(step: currentStep, stepIdx: currentStepIndex, distance: dist)

            // Advance step when within 20m of its endpoint
            if dist < 25 {
                advanceToNextStep(steps: steps)
                return
            }
        }

        // Update remaining distance
        remainingDistance = calcRemainingDistance(from: location, route: route)

        // ETA
        let speed = max(location.speed, 8.0) // at least 8 m/s as fallback
        let eta = remainingDistance / speed
        estimatedArrivalTime = Date().addingTimeInterval(eta)

        // Off-route check
        checkOffRoute(location: location)
    }

    private func advanceToNextStep(steps: [MKRouteStep]) {
        let next = currentStepIndex + 1
        if next >= steps.count {
            // Arrived
            announce("Sie haben Ihr Ziel erreicht.")
            estimatedArrivalTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.stopNavigation() }
            return
        }
        currentStepIndex = next
        let step = steps[next]
        updateInstruction(step: step)
        // Announce next step immediately
        let key = "\(next)-start"
        if !announcedKeys.contains(key) {
            announcedKeys.insert(key)
            announce(describeStep(step: step, withDistance: distanceToNextStep))
        }
    }

    // MARK: - Step Distance Announcements

    private func triggerAnnouncements(step: MKRouteStep, stepIdx: Int, distance: CLLocationDistance) {
        let thresholds: [(CLLocationDistance, String)] = [
            (500, "500 Metern"),
            (200, "200 Metern"),
            (80,  "80 Metern"),
            (30,  "30 Metern")
        ]
        for (threshold, label) in thresholds {
            let key = "\(stepIdx)-\(Int(threshold))"
            if distance <= threshold + 40 && distance > threshold - 40 && !announcedKeys.contains(key) {
                announcedKeys.insert(key)
                let direction = turnDirectionText(maneuver: step.maneuver)
                let street = step.instructions.isEmpty ? "" : " auf \(step.instructions)"
                announce("In \(label) \(direction)\(street).")
                return
            }
        }
        // Immediate
        let imm = "\(stepIdx)-immediate"
        if distance < 20 && !announcedKeys.contains(imm) {
            announcedKeys.insert(imm)
            announce("Jetzt \(turnDirectionText(maneuver: step.maneuver)).")
        }
    }

    // MARK: - Rerouting

    private func checkOffRoute(location: CLLocation) {
        guard !isRerouting, !routeCoordinates.isEmpty else { return }
        let minDist = routeCoordinates.map {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0

        if minDist > 90 {
            if offRouteSince == nil { offRouteSince = Date() }
            if let since = offRouteSince, Date().timeIntervalSince(since) > 4 {
                isRerouting = true
                offRouteSince = nil
                announce("Route wird neu berechnet.")
                rerouteTask?.cancel()
                rerouteTask = Task { await self.reroute() }
            }
        } else {
            offRouteSince = nil
        }
    }

    private func reroute() async {
        guard let dest = selectedDestination else { isRerouting = false; return }
        await calculateRoute(to: dest)
        currentStepIndex = 0
        announcedKeys = []
        isRerouting = false
        if let first = currentRoute?.steps.first {
            announce("Neue Route. " + describeStep(step: first, withDistance: nil))
        } else {
            errorMessage = "Keine neue Route gefunden."
        }
    }

    // MARK: - Instruction Helpers

    private func updateInstruction(step: MKRouteStep) {
        currentInstruction = step.instructions.isEmpty ? turnDirectionText(maneuver: step.maneuver) : step.instructions
        maneuverSymbol = symbolForManeuver(step.maneuver)
    }

    private func describeStep(step: MKRouteStep, withDistance dist: CLLocationDistance?) -> String {
        let direction = turnDirectionText(maneuver: step.maneuver)
        let distStr = dist.map { formatDistance($0) + " " } ?? ""
        let street = step.instructions.isEmpty ? "" : " auf \(step.instructions)"
        return "\(distStr)\(direction)\(street)."
    }

    private func turnDirectionText(maneuver: MKDirections.ManeuverType) -> String {
        switch maneuver {
        case .turnLeft:        return "links abbiegen"
        case .turnRight:       return "rechts abbiegen"
        case .turnSharpLeft:   return "scharf links abbiegen"
        case .turnSharpRight:  return "scharf rechts abbiegen"
        case .turnSlightLeft:  return "leicht links halten"
        case .turnSlightRight: return "leicht rechts halten"
        case .uturnLeft, .uturnRight: return "wenden"
        case .keepLeft:        return "links halten"
        case .keepRight:       return "rechts halten"
        case .rampLeft:        return "links auf die Auffahrt"
        case .rampRight:       return "rechts auf die Auffahrt"
        case .merge:           return "einfädeln"
        case .circle:          return "in den Kreisverkehr einfahren"
        case .ferry, .ferryTrain: return "Fähre nehmen"
        case .none:            return "geradeaus fahren"
        default:               return "geradeaus fahren"
        }
    }

    private func symbolForManeuver(_ m: MKDirections.ManeuverType) -> String {
        switch m {
        case .turnLeft, .turnSharpLeft:   return "arrow.turn.up.left"
        case .turnRight, .turnSharpRight: return "arrow.turn.up.right"
        case .turnSlightLeft, .keepLeft, .rampLeft:  return "arrow.up.left"
        case .turnSlightRight, .keepRight, .rampRight: return "arrow.up.right"
        case .uturnLeft, .uturnRight:     return "arrow.uturn.left"
        case .merge:                      return "arrow.merge"
        case .circle:                     return "arrow.circlepath"
        default:                          return "arrow.up"
        }
    }

    func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 {
            return "\(mins / 60) Std \(mins % 60) Min"
        }
        return "\(mins) Min"
    }

    // MARK: - Voice

    func announce(_ text: String) {
        synthesizer.stopSpeaking(at: .word)
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utt.rate = 0.50
        utt.preUtteranceDelay = 0.05
        synthesizer.speak(utt)
    }

    // MARK: - Geometry Helpers

    private func extractStepEndpoints(route: MKRoute) -> [CLLocationCoordinate2D] {
        route.steps.map { step in
            let n = step.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: n)
            step.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: n))
            return coords.last ?? route.polyline.coordinate
        }
    }

    private func extractPolylineCoords(polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let n = polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: n)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: n))
        // Sample every 5th point for performance
        return stride(from: 0, to: n, by: 5).map { coords[$0] }
    }

    private func calcRemainingDistance(from location: CLLocation, route: MKRoute) -> CLLocationDistance {
        route.steps[currentStepIndex...].reduce(0) { $0 + $1.distance }
    }
}

// MARK: - CLLocationManagerDelegate

extension NavigationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.userLocation = loc
            if self.isNavigating { self.updateProgress(location: loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.errorMessage = "GPS-Fehler: \(error.localizedDescription)" }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
                self.errorMessage = nil
            case .denied, .restricted:
                self.errorMessage = "Standort verweigert. Bitte in Einstellungen erlauben."
            default: break
            }
        }
    }
}
