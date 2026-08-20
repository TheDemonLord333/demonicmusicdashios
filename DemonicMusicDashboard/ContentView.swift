import SwiftUI

struct ContentView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @State private var isFullscreen = false

    var body: some View {
        ZStack {
            // Hintergrund füllt den gesamten Bildschirm (auch unter Statusbar/Notch)
            DemonicGradient.backgroundGradient
                .ignoresSafeArea()
            AmbientBlobs()

            // Inhalt bleibt innerhalb der Safe Area — GeometryReader OHNE ignoresSafeArea
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                if nowPlaying.spotify.isAuthorized {
                    if isLandscape {
                        LandscapeLayout(nowPlaying: nowPlaying)
                            .transition(.opacity)
                    } else {
                        PortraitLayout(nowPlaying: nowPlaying)
                            .transition(.opacity)
                    }
                } else {
                    LoginView(spotify: nowPlaying.spotify)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: nowPlaying.spotify.isAuthorized)

            // Vollbild-Button (nur wenn angemeldet)
            if nowPlaying.spotify.isAuthorized && !isFullscreen {
                VStack {
                    HStack {
                        Spacer()
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
                    Spacer()
                }
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
        .toolbar(isFullscreen ? .hidden : .visible, for: .tabBar)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Landscape Layout

struct LandscapeLayout: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @StateObject private var battery = BatteryMonitor()

    var body: some View {
        HStack(spacing: 0) {
            // GANZ LINKS: Batterie-Balken senkrecht
            VStack {
                Spacer()
                VerticalBatteryView(monitor: battery)
                Spacer()
            }
            .padding(.leading, 16)

            // MITTE: Album Art
            ZStack {
                if let track = nowPlaying.currentTrack {
                    AlbumArtView(url: track.albumArtURL, size: 220, image: track.albumArtImage)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    AlbumArtView(url: nil, size: 220)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)

            // RECHTS: Track Info
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(DemonicGradient.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(DemonicColor.demonPurple.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: DemonicColor.glowPurple, radius: 30)

                if let track = nowPlaying.currentTrack {
                    LandscapeTrackInfo(
                        track: track,
                        liveProgressMs: nowPlaying.liveProgressMs,
                        isSaved: nowPlaying.isSaved,
                        canSave: track.source == .spotify,
                        onToggleSaved: { Task { await nowPlaying.toggleSaved() } }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    IdleView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 40)
            .padding(.vertical, 24)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: nowPlaying.currentTrack?.title)
    }
}

// MARK: - Portrait Layout

struct PortraitLayout: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @StateObject private var battery = BatteryMonitor()

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                DemonicHeader()

                // TOP: Album Art
                ZStack {
                    if let track = nowPlaying.currentTrack {
                        AlbumArtSquareView(url: track.albumArtURL, size: 280, image: track.albumArtImage)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        AlbumArtSquareView(url: nil, size: 280)
                    }
                }
                .padding(.horizontal, 40)

                // BOTTOM: Track Info Card
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(DemonicGradient.cardGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(DemonicColor.demonPurple.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: DemonicColor.glowPurple, radius: 24)

                    if let track = nowPlaying.currentTrack {
                        PortraitTrackInfo(
                            track: track,
                            liveProgressMs: nowPlaying.liveProgressMs,
                            isSaved: nowPlaying.isSaved,
                            canSave: track.source == .spotify,
                            onToggleSaved: { Task { await nowPlaying.toggleSaved() } }
                        )
                        .padding(.vertical, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        IdleView()
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 20)

                // Batterie-Balken waagerecht (über dem Abmelden-Button)
                HorizontalBatteryView(monitor: battery)

                // Logout button
                Button(action: { nowPlaying.spotify.logout() }) {
                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DemonicColor.textMuted)
                }
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: nowPlaying.currentTrack?.title)
    }
}

// MARK: - Idle / No Track View

struct IdleView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(DemonicGradient.titleGradient)
                .scaleEffect(pulse ? 1.1 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

            Text("Nichts spielt gerade")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DemonicColor.textSecondary)

            Text("Starte Spotify und spiele etwas ab")
                .font(.system(size: 13))
                .foregroundColor(DemonicColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

// MARK: - Login View

struct LoginView: View {
    @ObservedObject var spotify: SpotifyService
    @State private var demonPulse = false

    var body: some View {
        VStack(spacing: 36) {
            // Demonic logo
            ZStack {
                Circle()
                    .fill(DemonicGradient.glowRing)
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                    .scaleEffect(demonPulse ? 1.2 : 0.9)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            demonPulse = true
                        }
                    }

                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DemonicGradient.titleGradient)
                    .shadow(color: DemonicColor.glowGreen, radius: 12)
            }

            VStack(spacing: 8) {
                Text("DEMONIC")
                    .font(.system(size: 36, weight: .black, design: .default))
                    .foregroundStyle(DemonicGradient.titleGradient)
                    .tracking(6)
                    .shadow(color: DemonicColor.glowGreen, radius: 10)

                Text("MUSIC DASHBOARD")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(DemonicColor.textMuted)
                    .tracking(4)
            }

            if SpotifyConfig.credentialsMissing {
                // SpotifyClientToken.json fehlt im Bundle
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(DemonicColor.demonMagenta)
                    Text("SpotifyClientToken.json fehlt")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DemonicColor.demonMagenta)
                    Text("Kopiere die Datei in den DemonicMusicDashboard-Ordner\nund baue die App erneut.")
                        .font(.system(size: 12))
                        .foregroundColor(DemonicColor.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .demonicCard()
                .padding(.horizontal, 20)
            } else {
                // Login Button
                Button(action: {
                    if let url = spotify.buildAuthURL() {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .bold))
                        Text("Mit Spotify verbinden")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [DemonicColor.spotifyGreen, DemonicColor.demonGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: DemonicColor.glowGreen, radius: 16)
                    )
                }
                .pulsingGlow(color: DemonicColor.spotifyGreen)

                if let error = spotify.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(DemonicColor.demonMagenta)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("Benötigt Spotify Premium oder Free\nDu wirst zu Spotify weitergeleitet")
                    .font(.system(size: 12))
                    .foregroundColor(DemonicColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

// MARK: - Demonic Header

struct DemonicHeader: View {
    var body: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: [DemonicColor.demonCrimson, DemonicColor.demonMagenta],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .font(.system(size: 18))

            Text("DEMONIC DASHBOARD")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(DemonicGradient.titleGradient)
                .tracking(3)

            Image(systemName: "flame.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: [DemonicColor.demonCrimson, DemonicColor.demonMagenta],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .font(.system(size: 18))
        }
    }
}

// MARK: - Ambient Background Blobs

struct AmbientBlobs: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(DemonicColor.demonPurple.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animate ? -80 : -120, y: animate ? -100 : -60)
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animate)

            Circle()
                .fill(DemonicColor.spotifyGreen.opacity(0.08))
                .frame(width: 250, height: 250)
                .blur(radius: 50)
                .offset(x: animate ? 100 : 60, y: animate ? 150 : 100)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animate)

            Circle()
                .fill(DemonicColor.demonCrimson.opacity(0.07))
                .frame(width: 200, height: 200)
                .blur(radius: 45)
                .offset(x: animate ? -60 : 40, y: animate ? 200 : 160)
                .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animate)
        }
        .onAppear { animate = true }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView(nowPlaying: NowPlayingService())
}
