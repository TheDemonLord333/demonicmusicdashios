import Foundation
import MediaPlayer

// MARK: - MediaPlayerService
// Liest MPNowPlayingInfoCenter alle 3 Sekunden aus und simuliert
// den Fortschritt mit einem 0.2s-Ticker (identisch zur Spotify-Logik).

@MainActor
final class MediaPlayerService: ObservableObject {

    @Published var currentTrack: UnifiedTrack?
    @Published var liveProgressMs: Int = 0
    @Published var isPlaying: Bool = false

    // Ticker-Anker (wie SpotifyService)
    private var progressAnchorSec: Double = 0
    private var progressAnchorDate: Date = Date()
    private var playbackRate: Double = 0

    private var pollTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?

    // MARK: - Lebenszyklus

    func start() {
        guard pollTask == nil else { return }
        poll() // Sofort ein erstes Mal abfragen
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                guard !Task.isCancelled else { break }
                poll()
            }
        }
        startTicker()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tickerTask?.cancel()
        tickerTask = nil
        currentTrack = nil
        liveProgressMs = 0
        isPlaying = false
    }

    // MARK: - Poll

    private func poll() {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo

        guard let info,
              let title = info[MPMediaItemPropertyTitle] as? String,
              !title.isEmpty
        else {
            currentTrack = nil
            isPlaying = false
            return
        }

        let artist   = info[MPMediaItemPropertyArtist] as? String ?? ""
        let durSec   = info[MPMediaItemPropertyPlaybackDuration] as? Double ?? 0
        let elapsed  = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0
        let rate     = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 1.0

        // Cover-Art aus dem MediaPlayer-Framework
        var artImage: UIImage? = nil
        if let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            artImage = artwork.image(at: CGSize(width: 400, height: 400))
        }

        // Quellen-Erkennung: Apple Music ↔ systemMusicPlayer
        let appleItem = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem
        let isApple   = appleItem != nil && appleItem?.title == title

        let track = UnifiedTrack(
            title: title,
            artist: artist,
            albumArtURL: nil,
            albumArtImage: artImage,
            durationMs: Int(durSec * 1000),
            source: isApple ? .appleMusic : .other,
            spotifyID: nil
        )

        currentTrack = track
        isPlaying = rate > 0

        // Anker für Smooth-Ticker setzen
        progressAnchorSec  = elapsed
        progressAnchorDate = Date()
        playbackRate       = rate

        // Direkt aktualisieren (verhindert kurzen Sprung beim ersten Tick)
        liveProgressMs = Int(elapsed * 1000)
    }

    // MARK: - Smooth-Ticker (0.2s)

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                guard !Task.isCancelled else { break }
                tick()
            }
        }
    }

    private func tick() {
        guard currentTrack != nil else { return }
        let live: Double
        if playbackRate > 0 {
            live = progressAnchorSec + Date().timeIntervalSince(progressAnchorDate) * playbackRate
        } else {
            live = progressAnchorSec
        }
        liveProgressMs = max(0, Int(live * 1000))
    }
}
