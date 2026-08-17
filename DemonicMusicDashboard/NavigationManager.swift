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

    private func advanceToNextStep(steps: [MKRoute.Step]) {
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

    private func triggerAnnouncements(step: MKRoute.Step, stepIdx: Int, distance: CLLocationDistance) {
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
                let direction = directionText(for: step.instructions)
                let street = step.instructions.isEmpty ? "" : " auf \(step.instructions)"
                announce("In \(label) \(direction)\(street).")
                return
            }
        }
        // Immediate
        let imm = "\(stepIdx)-immediate"
        if distance < 20 && !announcedKeys.contains(imm) {
            announcedKeys.insert(imm)
            announce("Jetzt \(directionText(for: step.instructions)).")
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

    private func updateInstruction(step: MKRoute.Step) {
        let text = step.instructions.isEmpty ? "Geradeaus fahren" : step.instructions
        currentInstruction = text
        maneuverSymbol = symbolForInstruction(text)
    }

    private func describeStep(step: MKRoute.Step, withDistance dist: CLLocationDistance?) -> String {
        let distStr = dist.map { formatDistance($0) + " " } ?? ""
        let text = step.instructions.isEmpty ? "geradeaus fahren" : step.instructions
        return "\(distStr)\(text)."
    }

    /// Derives a turn-direction phrase from the instruction text (German keywords).
    private func directionText(for instruction: String) -> String {
        let low = instruction.lowercased()
        if low.contains("wend") || low.contains("umkehr") { return "wenden" }
        if low.contains("scharf links")  { return "scharf links abbiegen" }
        if low.contains("scharf rechts") { return "scharf rechts abbiegen" }
        if low.contains("leicht links") || low.contains("halb links") { return "leicht links halten" }
        if low.contains("leicht rechts") || low.contains("halb rechts") { return "leicht rechts halten" }
        if low.contains("links")  { return "links abbiegen" }
        if low.contains("rechts") { return "rechts abbiegen" }
        if low.contains("kreisel") || low.contains("kreisverkehr") { return "in den Kreisverkehr einfahren" }
        if low.contains("fähre") || low.contains("ferry") { return "Fähre nehmen" }
        if low.contains("einfädeln") || low.contains("einfahren") { return "einfädeln" }
        return "geradeaus fahren"
    }

    /// Maps an instruction string to an SF Symbol name.
    private func symbolForInstruction(_ instruction: String) -> String {
        let low = instruction.lowercased()
        if low.contains("wend") || low.contains("umkehr") { return "arrow.uturn.left" }
        if low.contains("scharf links") || low.contains("links abbiegen") || low.contains("links ab") { return "arrow.turn.up.left" }
        if low.contains("scharf rechts") || low.contains("rechts abbiegen") || low.contains("rechts ab") { return "arrow.turn.up.right" }
        if low.contains("leicht links") || low.contains("halb links") { return "arrow.up.left" }
        if low.contains("leicht rechts") || low.contains("halb rechts") { return "arrow.up.right" }
        if low.contains("links") { return "arrow.turn.up.left" }
        if low.contains("rechts") { return "arrow.turn.up.right" }
        if low.contains("kreisel") || low.contains("kreisverkehr") { return "arrow.circlepath" }
        if low.contains("einfädeln") { return "arrow.merge" }
        return "arrow.up"
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
