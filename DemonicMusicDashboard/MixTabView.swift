import SwiftUI
import MapKit

// MARK: - MixTabView
// Kombiniert Navigation und Musik.
// Hochformat: Navigation oben, Musik unten, Batterie auf der Trennlinie.
// Querformat: Navigation links, Musik rechts, Batterie auf der Trennlinie.

struct MixTabView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var nav: NavigationManager
    @StateObject private var battery = BatteryMonitor()
    @State private var isFullscreen = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            ZStack {
                DemonicGradient.backgroundGradient.ignoresSafeArea()
                AmbientBlobs()

                if landscape {
                    landscapeMix(geo: geo)
                } else {
                    portraitMix(geo: geo)
                }

                // Vollbild-Verlassen-Button
                if isFullscreen {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { withAnimation { isFullscreen = false } }) {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(DemonicColor.textSecondary)
                                    .padding(10)
                                    .background(Circle().fill(DemonicColor.backgroundCard.opacity(0.85)))
                            }
                            .padding(.trailing, 16)
                            .accessibilityLabel("Vollbild verlassen")
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        }
        .toolbar(isFullscreen ? .hidden : .visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .onAppear {
            nav.requestPermission()
            nav.startLocationUpdates()
        }
        .accessibilityLabel("Mix")
    }

    // MARK: - Portrait

    @ViewBuilder
    private func portraitMix(geo: GeometryProxy) -> some View {
        let halfH = geo.size.height / 2

        VStack(spacing: 0) {
            // OBEN: Navigation
            ZStack(alignment: .bottom) {
                DemonicMapView(nav: nav, followsUser: nav.isNavigating)
                    .frame(height: halfH)

                // Navigations-Hinweise als kompakte Overlay-Karte
                if nav.isNavigating {
                    compactNavOverlay
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else if nav.selectedDestination != nil {
                    compactRoutePreview
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    compactSearchBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .frame(height: halfH)

            // UNTEN: Musik
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .fill(DemonicGradient.cardGradient)
                    .shadow(color: DemonicColor.glowPurple, radius: 20)

                mixMusicSection(isLandscape: false)
            }
            .frame(height: halfH)
        }
        // Batterie genau auf der Trennlinie (mittig zwischen oben und unten)
        .overlay(
            ZStack {
                HorizontalBatteryView(monitor: battery)
            }
            .offset(y: halfH / 2 - geo.size.height / 2 + halfH)
            ,
            alignment: .top
        )
        // Vollbild-Button
        .overlay(alignment: .topTrailing) {
            if !isFullscreen {
                Button(action: { withAnimation { isFullscreen = true } }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DemonicColor.textSecondary)
                        .padding(8)
                        .background(Circle().fill(DemonicColor.backgroundCard.opacity(0.85)))
                }
                .padding(.trailing, 12)
                .padding(.top, 8)
                .accessibilityLabel("Vollbild")
            }
        }
    }

    // MARK: - Landscape

    @ViewBuilder
    private func landscapeMix(geo: GeometryProxy) -> some View {
        let halfW = geo.size.width / 2

        HStack(spacing: 0) {
            // LINKS: Navigation
            ZStack(alignment: .bottomLeading) {
                DemonicMapView(nav: nav, followsUser: nav.isNavigating)
                    .frame(width: halfW)

                if nav.isNavigating {
                    compactNavOverlay
                        .padding(.all, 10)
                } else if nav.selectedDestination != nil {
                    compactRoutePreview
                        .padding(.all, 10)
                } else {
                    compactSearchBar
                        .padding(.all, 10)
                }
            }
            .frame(width: halfW)

            // RECHTS: Musik
            ZStack {
                DemonicGradient.cardGradient
                mixMusicSection(isLandscape: true)
            }
            .frame(width: halfW)
        }
        // Batterie genau auf der vertikalen Trennlinie
        .overlay(
            VerticalBatteryView(monitor: battery)
                .offset(x: halfW - geo.size.width / 2)
            ,
            alignment: .center
        )
        // Vollbild-Button
        .overlay(alignment: .topTrailing) {
            if !isFullscreen {
                Button(action: { withAnimation { isFullscreen = true } }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DemonicColor.textSecondary)
                        .padding(8)
                        .background(Circle().fill(DemonicColor.backgroundCard.opacity(0.85)))
                }
                .padding(.trailing, 12)
                .padding(.top, 8)
                .accessibilityLabel("Vollbild")
            }
        }
    }

    // MARK: - Musik-Bereich (Mix)

    @ViewBuilder
    private func mixMusicSection(isLandscape: Bool) -> some View {
        if let track = nowPlaying.currentTrack {
            // Track erkannt (Spotify, Apple Music, Andere)
            ScrollView {
                VStack(spacing: 14) {
                    // Cover
                    AlbumArtSquareView(
                        url: track.albumArtURL,
                        size: isLandscape ? 120 : 160,
                        image: track.albumArtImage
                    )
                    .padding(.top, 12)

                    // Quellen-Badge
                    MusicSourceBadge(source: track.source)

                    // Titel
                    Text(track.title)
                        .font(.system(size: isLandscape ? 16 : 20, weight: .black))
                        .foregroundStyle(DemonicGradient.titleGradient)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: DemonicColor.glowGreen, radius: 6)
                        .padding(.horizontal, 12)

                    // Künstler
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DemonicColor.demonPurple)
                        Text(track.artist)
                            .font(.system(size: isLandscape ? 13 : 15, weight: .semibold))
                            .foregroundColor(DemonicColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    // Zeitstrahl
                    VStack(spacing: 4) {
                        let progress = track.durationMs > 0
                            ? Double(nowPlaying.liveProgressMs) / Double(track.durationMs)
                            : 0
                        DemonicProgressBar(progress: progress)
                            .padding(.horizontal, 16)
                        HStack {
                            Text(formatTime(nowPlaying.liveProgressMs))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DemonicColor.textMuted)
                            Spacer()
                            Text(formatTime(track.durationMs))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DemonicColor.textMuted)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Like-Button nur für Spotify
                    if track.source == .spotify {
                        LikeButton(isSaved: nowPlaying.isSaved) {
                            Task { await nowPlaying.toggleSaved() }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
        } else if !nowPlaying.spotify.isAuthorized {
            // Spotify nicht angemeldet und nichts anderes spielt
            VStack(spacing: 12) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 36))
                    .foregroundStyle(DemonicGradient.titleGradient)
                Text("Spotify nicht verbunden")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DemonicColor.textSecondary)
                Text("Im Musik-Tab anmelden oder\nandere Musik-App starten")
                    .font(.system(size: 12))
                    .foregroundColor(DemonicColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Angemeldet aber nichts spielt
            VStack(spacing: 10) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(DemonicGradient.titleGradient)
                Text("Nichts spielt gerade")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DemonicColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Kompakte Nav-Komponenten für Mix

    private var compactSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DemonicColor.spotifyGreen)
                .font(.system(size: 13))
            TextField("Ziel suchen…", text: $nav.searchQuery)
                .foregroundColor(DemonicColor.textPrimary)
                .tint(DemonicColor.spotifyGreen)
                .font(.system(size: 13))
                .onChange(of: nav.searchQuery) { q in nav.search(query: q) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DemonicColor.backgroundCard.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DemonicColor.demonPurple.opacity(0.3), lineWidth: 1))
        )
    }

    private var compactRoutePreview: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nav.selectedDestination?.name ?? "Ziel")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DemonicColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(nav.formatDistance(nav.routeDistance))
                        .font(.system(size: 11))
                        .foregroundColor(DemonicColor.spotifyGreen)
                    Text(nav.formatDuration(nav.routeETA))
                        .font(.system(size: 11))
                        .foregroundColor(DemonicColor.demonGreen)
                }
            }
            Spacer()
            Button(action: { nav.startNavigation() }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(8)
                    .background(Circle().fill(DemonicColor.spotifyGreen))
            }
            .accessibilityLabel("Navigation starten")
            Button(action: { nav.cancelRoutePreview() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundColor(DemonicColor.textMuted)
                    .padding(6)
                    .background(Circle().fill(DemonicColor.backgroundCard))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DemonicColor.backgroundCard.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DemonicColor.demonPurple.opacity(0.3), lineWidth: 1))
        )
    }

    private var compactNavOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: nav.maneuverSymbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DemonicGradient.titleGradient)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(nav.formatDistance(nav.distanceToNextStep))
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(DemonicColor.demonGreen)
                Text(nav.currentInstruction)
                    .font(.system(size: 11))
                    .foregroundColor(DemonicColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let eta = nav.estimatedArrivalTime {
                Text(eta.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DemonicColor.textMuted)
            }
            Button(action: { nav.stopNavigation() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DemonicColor.demonMagenta)
                    .padding(6)
                    .background(Circle().fill(DemonicColor.backgroundCard))
            }
            .accessibilityLabel("Navigation beenden")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DemonicColor.backgroundCard.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DemonicColor.spotifyGreen.opacity(0.3), lineWidth: 1))
                .shadow(color: DemonicColor.glowGreen, radius: 8)
        )
    }

    private func formatTime(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
