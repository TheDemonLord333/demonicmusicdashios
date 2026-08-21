import Foundation
import Combine
import MediaPlayer

// MARK: - MediaPlayerService
// Liest Apple Music via MPMusicPlayerController.systemMusicPlayer.
// Benötigt Media Library Berechtigung (NSAppleMusicUsageDescription).
// Amazon Music und andere Apps haben kein öffentliches iOS-API.

@MainActor
final class MediaPlayerService: ObservableObject {

    @Published var currentTrack: UnifiedTrack?
    @Published var liveProgressMs: Int = 0
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined

    // Ticker-Anker
    private var progressAnchorSec: Double = 0
    private var progressAnchorDate: Date = Date()
    private var playbackRate: Double = 0

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var tickerTask: Task<Void, Never>?
    private var started = false

    // MARK: - Berechtigung anfordern + starten

    func requestAuthorizationAndStart() {
        let status = MPMediaLibrary.authorizationStatus()
        authorizationStatus = status

        switch status {
        case .authorized:
            startListening()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    self?.authorizationStatus = newStatus
                    if newStatus == .authorized {
                        self?.startListening()
                    }
                }
            }
        default:
            break // verweigert — nichts tun
        }
    }

    // MARK: - Listening starten

    private func startListening() {
        guard !started else { return }
        started = true

        // Benachrichtigungen für Track- und Status-Änderungen
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        player.beginGeneratingPlaybackNotifications()

        // Erstmalig pollen
        poll()
        startTicker()
    }

    func stop() {
        guard started else { return }
        started = false
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
        tickerTask?.cancel()
        tickerTask = nil
        currentTrack = nil
        liveProgressMs = 0
    }

    // MARK: - Notifications

    @objc private func nowPlayingItemChanged() {
        poll()
    }

    @objc private func playbackStateChanged() {
        updateAnchor()
    }

    // MARK: - Poll (bei Notification oder manuell)

    private func poll() {
        guard let item = player.nowPlayingItem else {
            currentTrack = nil
            return
        }

        let artImage = item.artwork?.image(at: CGSize(width: 400, height: 400))

        currentTrack = UnifiedTrack(
            title: item.title ?? "",
            artist: item.artist ?? "",
            albumArtURL: nil,
            albumArtImage: artImage,
            durationMs: Int(item.playbackDuration * 1000),
            source: .appleMusic,
            spotifyID: nil
        )

        updateAnchor()
    }

    private func updateAnchor() {
        progressAnchorSec  = player.currentPlaybackTime
        progressAnchorDate = Date()
        playbackRate       = player.playbackState == .playing ? 1.0 : 0.0
        liveProgressMs     = Int(progressAnchorSec * 1000)
    }

    // MARK: - Smooth-Ticker (0.2s)

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { break }
                tick()
            }
        }
    }

    private func tick() {
        guard currentTrack != nil else { return }
        let live = playbackRate > 0
            ? progressAnchorSec + Date().timeIntervalSince(progressAnchorDate) * playbackRate
            : progressAnchorSec
        liveProgressMs = max(0, Int(live * 1000))
    }
}
