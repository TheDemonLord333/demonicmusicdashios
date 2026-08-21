import Foundation
import Combine

// MARK: - NowPlayingService
// Vereinheitlichte Musik-Quelle: Spotify hat Priorität, Fallback auf MediaPlayer.
// Views binden sich an diese Klasse statt direkt an SpotifyService.

@MainActor
final class NowPlayingService: ObservableObject {

    // MARK: - Sub-Services (intern verwaltet)
    let spotify: SpotifyService
    let mediaPlayer: MediaPlayerService

    // MARK: - Unified Output
    @Published var currentTrack: UnifiedTrack?
    @Published var liveProgressMs: Int = 0
    @Published var isSaved: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        self.spotify      = SpotifyService()
        self.mediaPlayer  = MediaPlayerService()

        mediaPlayer.requestAuthorizationAndStart()
        setupBindings()
    }

    // MARK: - Combine-Bindings

    private func setupBindings() {
        // Spotify-Track → UnifiedTrack (Priorität)
        // MediaPlayer-Track als Fallback
        Publishers.CombineLatest4(
            spotify.$currentTrack,
            spotify.$liveProgressMs,
            mediaPlayer.$currentTrack,
            mediaPlayer.$liveProgressMs
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] spotifyTrack, spotifyMs, mpTrack, mpMs in
            guard let self else { return }

            if let st = spotifyTrack {
                // Spotify spielt → in UnifiedTrack umwandeln
                self.currentTrack = UnifiedTrack(
                    title: st.title,
                    artist: st.artist,
                    albumArtURL: st.albumArtURL,
                    albumArtImage: nil,
                    durationMs: st.durationMs,
                    source: .spotify,
                    spotifyID: st.id
                )
                self.liveProgressMs = spotifyMs

            } else if let mt = mpTrack {
                // Apple Music spielt
                self.currentTrack = mt
                self.liveProgressMs = mpMs

            } else {
                self.currentTrack = nil
                self.liveProgressMs = 0
            }
        }
        .store(in: &cancellables)

        // isSaved direkt von Spotify übernehmen
        spotify.$isSaved
            .receive(on: RunLoop.main)
            .assign(to: &$isSaved)
    }

    // MARK: - Aktionen

    /// Like-Toggle — nur für Spotify-Tracks verfügbar
    func toggleSaved() async {
        guard currentTrack?.source == .spotify else { return }
        await spotify.toggleSaved()
    }

    /// Spotify OAuth-Callback weiterleiten
    func handleCallback(url: URL) {
        spotify.handleCallback(url: url)
    }
}
