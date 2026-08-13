import SwiftUI
import MapKit

// MARK: - NavigationTabView
// Vollständige Navigation ohne Musikdetails, ohne Batterieanzeige.

struct NavigationTabView: View {
    @ObservedObject var nav: NavigationManager
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            DemonicGradient.backgroundGradient.ignoresSafeArea()

            GeometryReader { geo in
                ZStack(alignment: .top) {
                    // KARTE (füllt den ganzen Bereich)
                    DemonicMapView(nav: nav, followsUser: nav.isNavigating)
                        .ignoresSafeArea(edges: .bottom)

                    // ÜBERBLENDETE ELEMENTE
                    VStack(spacing: 0) {
                        // Suchleiste oben
                        if !nav.isNavigating {
                            searchBar
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }

                        // Suchergebnisse
                        if !nav.searchResults.isEmpty && !nav.isNavigating {
                            searchResultsList
                                .padding(.horizontal, 16)
                        }

                        Spacer()

                        // Route-Vorschau-Karte (vor dem Starten)
                        if nav.selectedDestination != nil && !nav.isNavigating {
                            routePreviewCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }

                        // Navigations-HUD (während aktiver Navigation)
                        if nav.isNavigating {
                            navigationHUD
                                .padding(.bottom, 16)
                        }
                    }
                }
            }

            // Permission-Overlay
            if nav.authorizationStatus == .denied || nav.authorizationStatus == .restricted {
                permissionDeniedOverlay
            } else if nav.authorizationStatus == .notDetermined {
                permissionRequestOverlay
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            nav.requestPermission()
            nav.startLocationUpdates()
        }
        .onDisappear {
            nav.stopLocationUpdatesIfIdle()
        }
        .accessibilityLabel("Navigation")
    }

    // MARK: - Suchleiste

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DemonicColor.spotifyGreen)
                .font(.system(size: 16))

            TextField("Ziel suchen…", text: $nav.searchQuery)
                .foregroundColor(DemonicColor.textPrimary)
                .tint(DemonicColor.spotifyGreen)
                .focused($searchFocused)
                .onSubmit { nav.search(query: nav.searchQuery) }
                .onChange(of: nav.searchQuery) { q in nav.search(query: q) }
                .accessibilityLabel("Ziel eingeben")

            if !nav.searchQuery.isEmpty {
                Button(action: { nav.clearSearch(); searchFocused = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DemonicColor.textMuted)
                }
                .accessibilityLabel("Suche löschen")
            }

            if nav.isSearching {
                ProgressView()
                    .tint(DemonicColor.spotifyGreen)
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DemonicColor.backgroundCard.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(DemonicColor.demonPurple.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: DemonicColor.glowPurple, radius: 10)
        )
    }

    // MARK: - Suchergebnisse

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(nav.searchResults.prefix(8), id: \.self) { item in
                    Button(action: {
                        searchFocused = false
                        nav.clearSearch()
                        Task { await nav.calculateRoute(to: item) }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(DemonicColor.demonPurple)
                                .font(.system(size: 20))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unbekannt")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DemonicColor.textPrimary)
                                if let addr = item.placemark.title {
                                    Text(addr)
                                        .font(.system(size: 12))
                                        .foregroundColor(DemonicColor.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if item !== nav.searchResults.prefix(8).last {
                        Divider().background(DemonicColor.textMuted.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DemonicColor.backgroundCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(DemonicColor.demonPurple.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12)
        )
    }

    // MARK: - Route-Vorschau-Karte

    private var routePreviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "flag.checkered")
                    .foregroundColor(DemonicColor.demonPurple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nav.selectedDestination?.name ?? "Ziel")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DemonicColor.textPrimary)
                    if let addr = nav.selectedDestination?.placemark.title {
                        Text(addr)
                            .font(.system(size: 12))
                            .foregroundColor(DemonicColor.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button(action: { nav.cancelRoutePreview() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(DemonicColor.textMuted)
                        .padding(6)
                }
            }

            if nav.routeDistance > 0 {
                HStack(spacing: 20) {
                    Label(nav.formatDistance(nav.routeDistance), systemImage: "arrow.triangle.swap")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DemonicColor.spotifyGreen)
                    Label(nav.formatDuration(nav.routeETA), systemImage: "clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DemonicColor.demonGreen)
                    Spacer()
                }
                .padding(.horizontal, 4)

                Button(action: { nav.startNavigation() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                        Text("Navigation starten")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [DemonicColor.spotifyGreen, DemonicColor.demonGreen],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .shadow(color: DemonicColor.glowGreen, radius: 10)
                    )
                }
                .accessibilityLabel("Navigation starten")
            } else {
                ProgressView()
                    .tint(DemonicColor.spotifyGreen)
                Text("Route wird berechnet…")
                    .font(.system(size: 13))
                    .foregroundColor(DemonicColor.textMuted)
            }

            if let err = nav.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(DemonicColor.demonMagenta)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(DemonicColor.backgroundCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DemonicColor.demonPurple.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: DemonicColor.glowPurple, radius: 16)
        )
    }

    // MARK: - Navigations-HUD

    private var navigationHUD: some View {
        VStack(spacing: 10) {
            // Aktuelle Anweisung
            HStack(spacing: 14) {
                Image(systemName: nav.maneuverSymbol)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DemonicGradient.titleGradient)
                    .frame(width: 44)
                    .accessibilityLabel("Abbiege-Richtung")

                VStack(alignment: .leading, spacing: 3) {
                    Text(nav.formatDistance(nav.distanceToNextStep))
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(DemonicColor.demonGreen)
                    Text(nav.currentInstruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DemonicColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Divider().background(DemonicColor.demonPurple.opacity(0.3))

            // Restdistanz + Ankunft
            HStack {
                Label(nav.formatDistance(nav.remainingDistance), systemImage: "arrow.triangle.swap")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DemonicColor.spotifyGreen)
                Spacer()
                if let eta = nav.estimatedArrivalTime {
                    Label(eta.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DemonicColor.textSecondary)
                }
                Spacer()
                if nav.isRerouting {
                    Label("Neu berechnen…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(DemonicColor.demonMagenta)
                }
                // Stop-Button
                Button(action: { nav.stopNavigation() }) {
                    Label("Beenden", systemImage: "stop.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DemonicColor.demonMagenta)
                }
                .accessibilityLabel("Navigation beenden")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(DemonicColor.backgroundCard.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DemonicColor.spotifyGreen.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: DemonicColor.glowGreen, radius: 14)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Permission Overlays

    private var permissionRequestOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(DemonicGradient.titleGradient)

            Text("Standort benötigt")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(DemonicGradient.titleGradient)

            Text("Für die Navigation wird dein aktueller Standort benötigt.")
                .font(.system(size: 14))
                .foregroundColor(DemonicColor.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: { nav.requestPermission() }) {
                Label("Standort erlauben", systemImage: "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(LinearGradient(
                            colors: [DemonicColor.spotifyGreen, DemonicColor.demonGreen],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .shadow(color: DemonicColor.glowGreen, radius: 10)
                    )
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(DemonicGradient.cardGradient)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(DemonicColor.demonPurple.opacity(0.3), lineWidth: 1))
        )
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DemonicGradient.backgroundGradient.ignoresSafeArea())
    }

    private var permissionDeniedOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(DemonicColor.demonMagenta)

            Text("Standort verweigert")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(DemonicColor.demonMagenta)

            Text("Bitte erlaube den Standortzugriff in den Einstellungen unter Datenschutz → Ortungsdienste.")
                .font(.system(size: 13))
                .foregroundColor(DemonicColor.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Label("Einstellungen öffnen", systemImage: "gear")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(DemonicColor.demonMagenta))
            }
        }
        .padding(36)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(DemonicGradient.cardGradient)
        )
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DemonicGradient.backgroundGradient.ignoresSafeArea())
    }
}

// Hilfsextension um zwei MKMapItem-Referenzen vergleichen zu können
extension MKMapItem: @retroactive Equatable {
    public static func == (lhs: MKMapItem, rhs: MKMapItem) -> Bool {
        lhs === rhs
    }
}
