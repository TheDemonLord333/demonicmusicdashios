import SwiftUI

// MARK: - AppTabView
// Root-View: Verwaltet die drei Tabs und die gemeinsam genutzten Services.

struct AppTabView: View {
    @StateObject private var spotify = SpotifyService()
    @StateObject private var navManager = NavigationManager()

    var body: some View {
        TabView {
            // MARK: Tab 1 – Musik
            MusicTabWrapper(spotify: spotify)
                .tabItem {
                    Label("Musik", systemImage: "music.note")
                }
                .tag(0)

            // MARK: Tab 2 – Navigation
            NavigationTabView(nav: navManager)
                .tabItem {
                    Label("Navigation", systemImage: "map.fill")
                }
                .tag(1)

            // MARK: Tab 3 – Mix
            MixTabView(spotify: spotify, nav: navManager)
                .tabItem {
                    Label("Mix", systemImage: "rectangle.split.2x1.fill")
                }
                .tag(2)
        }
        .tint(DemonicColor.spotifyGreen)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            spotify.handleCallback(url: url)
        }
    }
}

// MARK: - MusicTabWrapper
// Wraps ContentView (which still handles its own fullscreen state).

struct MusicTabWrapper: View {
    @ObservedObject var spotify: SpotifyService

    var body: some View {
        ContentView(spotify: spotify)
    }
}
