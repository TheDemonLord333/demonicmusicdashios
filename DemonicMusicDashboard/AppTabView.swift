import SwiftUI

// MARK: - AppTabView
// Root-View: Verwaltet die drei Tabs und die gemeinsam genutzten Services.

struct AppTabView: View {
    @StateObject private var nowPlaying = NowPlayingService()
    @StateObject private var navManager = NavigationManager()

    var body: some View {
        TabView {
            // MARK: Tab 1 – Musik
            ContentView(nowPlaying: nowPlaying)
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
            MixTabView(nowPlaying: nowPlaying, nav: navManager)
                .tabItem {
                    Label("Mix", systemImage: "rectangle.split.2x1.fill")
                }
                .tag(2)
        }
        .tint(DemonicColor.spotifyGreen)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            nowPlaying.handleCallback(url: url)
        }
    }
}
