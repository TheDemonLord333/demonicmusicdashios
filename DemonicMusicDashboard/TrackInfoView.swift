import SwiftUI

// MARK: - Scrolling Title Text

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width
            ZStack(alignment: .leading) {
                if textWidth > containerW {
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .fixedSize()
                        .offset(x: offset)
                        .onAppear {
                            containerWidth = containerW
                            withAnimation(
                                .linear(duration: Double(textWidth) / 40)
                                .repeatForever(autoreverses: false)
                                .delay(1.5)
                            ) {
                                offset = -(textWidth + 40)
                            }
                        }
                        .onChange(of: text) { _ in
                            offset = 0
                            withAnimation(
                                .linear(duration: Double(textWidth) / 40)
                                .repeatForever(autoreverses: false)
                                .delay(1.5)
                            ) {
                                offset = -(textWidth + 40)
                            }
                        }
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                }
            }
            .background(
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background(GeometryReader { tGeo in
                        Color.clear.onAppear { textWidth = tGeo.size.width }
                    })
            )
            .clipped()
        }
    }
}

// MARK: - Progress Bar

struct DemonicProgressBar: View {
    let progress: Double   // 0.0 – 1.0
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DemonicColor.backgroundElevated)
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [DemonicColor.spotifyGreen, DemonicColor.demonGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * animatedProgress, height: 4)
                    .shadow(color: DemonicColor.glowGreen, radius: 4)

                // Glowing dot
                Circle()
                    .fill(DemonicColor.demonGreen)
                    .frame(width: 10, height: 10)
                    .shadow(color: DemonicColor.glowGreen, radius: 6)
                    .offset(x: max(0, geo.size.width * animatedProgress - 5))
            }
        }
        .frame(height: 10)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { animatedProgress = progress } }
        .onChange(of: progress) { newVal in
            withAnimation(.easeOut(duration: 0.5)) { animatedProgress = newVal }
        }
    }
}

// MARK: - Track Info (Landscape: right panel)

struct LandscapeTrackInfo: View {
    let track: UnifiedTrack
    let liveProgressMs: Int
    let isSaved: Bool
    var canSave: Bool = true
    let onToggleSaved: () -> Void

    var progress: Double {
        guard track.durationMs > 0 else { return 0 }
        return Double(liveProgressMs) / Double(track.durationMs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            // Quellen-Badge + Like-Button
            HStack(spacing: 8) {
                MusicSourceBadge(source: track.source)
                Spacer()
                if canSave {
                    LikeButton(isSaved: isSaved, action: onToggleSaved)
                }
            }

            // Title
            Text(track.title)
                .font(.system(size: 32, weight: .black, design: .default))
                .foregroundStyle(DemonicGradient.titleGradient)
                .lineLimit(2)
                .shadow(color: DemonicColor.glowGreen, radius: 8)

            // Artist
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .foregroundColor(DemonicColor.demonPurple)
                    .font(.system(size: 14))
                Text(track.artist)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DemonicColor.textSecondary)
            }

            // Progress
            VStack(spacing: 6) {
                DemonicProgressBar(progress: progress)
                HStack {
                    Text(formatTime(liveProgressMs))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DemonicColor.textMuted)
                    Spacer()
                    Text(formatTime(track.durationMs))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DemonicColor.textMuted)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private func formatTime(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Track Info (Portrait: below cover)

struct PortraitTrackInfo: View {
    let track: UnifiedTrack
    let liveProgressMs: Int
    let isSaved: Bool
    var canSave: Bool = true
    let onToggleSaved: () -> Void

    var progress: Double {
        guard track.durationMs > 0 else { return 0 }
        return Double(liveProgressMs) / Double(track.durationMs)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Quellen-Badge + Like-Button
            HStack(spacing: 6) {
                MusicSourceBadge(source: track.source)
                Spacer()
                if canSave {
                    LikeButton(isSaved: isSaved, action: onToggleSaved)
                }
            }
            .padding(.horizontal, 4)

            // Title
            Text(track.title)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(DemonicGradient.titleGradient)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .shadow(color: DemonicColor.glowGreen, radius: 8)

            // Artist
            HStack(spacing: 5) {
                Image(systemName: "person.fill")
                    .foregroundColor(DemonicColor.demonPurple)
                    .font(.system(size: 13))
                Text(track.artist)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(DemonicColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Progress
            VStack(spacing: 5) {
                DemonicProgressBar(progress: progress)
                HStack {
                    Text(formatTime(liveProgressMs))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DemonicColor.textMuted)
                    Spacer()
                    Text(formatTime(track.durationMs))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DemonicColor.textMuted)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
    }

    private func formatTime(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Quellen-Badge

struct MusicSourceBadge: View {
    let source: UnifiedTrack.MusicSource

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: source.sfSymbol)
                .font(.system(size: 10, weight: .bold))
            Text(source.displayName)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(Color(hex: source.badgeColorHex))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(hex: source.badgeColorHex).opacity(0.15))
                .overlay(Capsule().stroke(Color(hex: source.badgeColorHex).opacity(0.35), lineWidth: 1))
        )
    }
}

// MARK: - Like / Save Button

struct LikeButton: View {
    let isSaved: Bool
    let action: () -> Void
    @State private var bounce = false

    var body: some View {
        Button(action: {
            bounce = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bounce = false }
        }) {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    isSaved
                        ? LinearGradient(colors: [DemonicColor.demonMagenta, DemonicColor.demonCrimson], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [DemonicColor.textMuted, DemonicColor.textMuted], startPoint: .top, endPoint: .bottom)
                )
                .scaleEffect(bounce ? 1.35 : 1.0)
                .shadow(color: isSaved ? DemonicColor.glowCrimson : .clear, radius: 8)
                .animation(.spring(response: 0.3, dampingFraction: 0.4), value: bounce)
                .animation(.easeInOut(duration: 0.2), value: isSaved)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animated Playing Bars

struct PlayingBar: View {
    let delay: Double
    let isPlaying: Bool
    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(DemonicColor.spotifyGreen)
            .frame(width: 3, height: height)
            .animation(
                isPlaying
                    ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(delay)
                    : .default,
                value: height
            )
            .onAppear { if isPlaying { height = 16 } }
            .onChange(of: isPlaying) { playing in
                height = playing ? 16 : 4
            }
    }
}
