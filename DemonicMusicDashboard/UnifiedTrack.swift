import UIKit

// MARK: - UnifiedTrack
// Gemeinsames Track-Modell für alle Musik-Quellen (Spotify, Apple Music, Andere).

struct UnifiedTrack: Equatable {

    // MARK: - Quelle
    // Unterstützte Quellen:
    // – .spotify    → Spotify API (OAuth, Like-Button verfügbar)
    // – .appleMusic → MPMusicPlayerController.systemMusicPlayer (Berechtigung nötig)
    // Hinweis: Amazon Music hat kein öffentliches iOS-API und kann nicht erkannt werden.
    enum MusicSource: Equatable {
        case spotify
        case appleMusic

        var displayName: String {
            switch self {
            case .spotify:    return "Spotify"
            case .appleMusic: return "Apple Music"
            }
        }

        /// SF-Symbol-Name für das Quellen-Badge
        var sfSymbol: String {
            switch self {
            case .spotify:    return "music.note.list"
            case .appleMusic: return "applelogo"
            }
        }

        /// Akzentfarbe im Badge
        var badgeColorHex: String {
            switch self {
            case .spotify:    return "#1DB954"
            case .appleMusic: return "#FC3C44"
            }
        }
    }

    // MARK: - Felder
    let title: String
    let artist: String

    /// Für URL-basiertes Cover-Artwork (Spotify)
    let albumArtURL: URL?
    /// Für bild-basiertes Cover-Artwork (Apple Music / MediaPlayer)
    let albumArtImage: UIImage?

    let durationMs: Int
    let source: MusicSource

    /// Nur gesetzt wenn source == .spotify (für Like-Button)
    let spotifyID: String?

    // MARK: - Equatable (nach Titel + Künstler + Quelle)
    static func == (lhs: UnifiedTrack, rhs: UnifiedTrack) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.source == rhs.source
    }
}
