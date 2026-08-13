import SwiftUI
import MapKit

// MARK: - DemonicMapView
// UIViewRepresentable wrapping MKMapView with demonic dark styling.
// Used by both NavigationTabView and MixTabView via the shared NavigationManager.

struct DemonicMapView: UIViewRepresentable {
    @ObservedObject var nav: NavigationManager
    var followsUser: Bool = true

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.overrideUserInterfaceStyle = .dark
        map.mapType = .standard
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.isZoomEnabled = true
        map.isScrollEnabled = true

        // Kompass-Button unten rechts
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        map.addSubview(compass)
        compass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            compass.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            compass.bottomAnchor.constraint(equalTo: map.bottomAnchor, constant: -12)
        ])

        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // --- Route overlay ---
        let existingPolylines = mapView.overlays.compactMap { $0 as? MKPolyline }
        if let route = nav.currentRoute {
            // Nur neu hinzufügen, wenn sich die Route geändert hat
            if existingPolylines.first !== route.polyline {
                mapView.removeOverlays(mapView.overlays)
                mapView.addOverlay(route.polyline, level: .aboveRoads)
            }
        } else if !existingPolylines.isEmpty {
            mapView.removeOverlays(mapView.overlays)
        }

        // --- Destination annotation ---
        let nonUserAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        if let dest = nav.selectedDestination {
            let destCoord = dest.placemark.coordinate
            let existing = nonUserAnnotations.first as? MKPointAnnotation
            if existing == nil || existing?.coordinate.latitude != destCoord.latitude {
                mapView.removeAnnotations(nonUserAnnotations)
                let pin = MKPointAnnotation()
                pin.coordinate = destCoord
                pin.title = dest.name ?? "Ziel"
                mapView.addAnnotation(pin)
            }
        } else if !nonUserAnnotations.isEmpty {
            mapView.removeAnnotations(nonUserAnnotations)
        }

        // --- Camera ---
        if nav.isNavigating, followsUser, let loc = nav.userLocation {
            let camera = MKMapCamera(
                lookingAtCenter: loc.coordinate,
                fromDistance: 600,
                pitch: 0,
                heading: loc.course >= 0 ? loc.course : 0
            )
            mapView.setCamera(camera, animated: true)
        } else if !nav.isNavigating, let route = nav.currentRoute {
            // Zeige die gesamte Route
            let padding = UIEdgeInsets(top: 60, left: 40, bottom: 80, right: 40)
            mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: padding, animated: true)
        } else if !nav.isNavigating, let loc = nav.userLocation, nav.selectedDestination == nil {
            let region = MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 1200, longitudinalMeters: 1200
            )
            if abs(mapView.region.center.latitude - loc.coordinate.latitude) > 0.005 {
                mapView.setRegion(region, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(red: 0.113, green: 0.725, blue: 0.329, alpha: 1) // Spotify Green
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            // Glow effect via shadow
            renderer.strokeColor = renderer.strokeColor?.withAlphaComponent(0.9)
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dest")
            view.markerTintColor = UIColor(red: 0.482, green: 0.184, blue: 0.745, alpha: 1) // Demon Purple
            view.glyphImage = UIImage(systemName: "flag.checkered")
            view.titleVisibility = .visible
            return view
        }
    }
}
