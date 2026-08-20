import SwiftUI

struct AlbumArtView: View {
    let url: URL?
    let size: CGFloat
    var image: UIImage? = nil   // direktes UIImage (z.B. von MediaPlayer)

    @State private var rotationAngle: Double = 0
    @State private var imageData: Data?

    var body: some View {
        ZStack {
            // Outer demonic glow ring
            Circle()
                .fill(DemonicGradient.glowRing)
                .frame(width: size + 16, height: size + 16)
                .blur(radius: 8)
                .opacity(0.7)
                .rotationEffect(.degrees(rotationAngle))
                .onAppear {
                    withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                        rotationAngle = 360
                    }
                }

            // Album art circle
            Group {
                if let img = resolvedImage() {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Circle()
                            .fill(DemonicColor.backgroundCard)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.35))
                            .foregroundStyle(DemonicGradient.titleGradient)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(DemonicColor.demonPurple.opacity(0.4), lineWidth: 2)
            )
            // Center vinyl hole
            .overlay(
                Circle()
                    .fill(DemonicColor.backgroundDeep)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .overlay(
                        Circle()
                            .fill(DemonicColor.spotifyGreen.opacity(0.6))
                            .frame(width: size * 0.06, height: size * 0.06)
                    )
            )
            .shadow(color: DemonicColor.glowPurple, radius: 15)
            .shadow(color: DemonicColor.glowGreen.opacity(0.3), radius: 30)
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func resolvedImage() -> UIImage? {
        if let img = image { return img }
        if let data = imageData { return UIImage(data: data) }
        return nil
    }

    private func loadImage() async {
        guard let url else { imageData = nil; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run { imageData = data }
        } catch {
            await MainActor.run { imageData = nil }
        }
    }
}

// MARK: - Square variant for portrait layout

struct AlbumArtSquareView: View {
    let url: URL?
    let size: CGFloat
    var image: UIImage? = nil   // direktes UIImage (z.B. von MediaPlayer)

    @State private var imageData: Data?
    @State private var shimmer = false

    var body: some View {
        ZStack {
            // Demonic corner glow
            RoundedRectangle(cornerRadius: 24)
                .fill(DemonicGradient.glowRing)
                .frame(width: size + 20, height: size + 20)
                .blur(radius: 12)
                .opacity(shimmer ? 0.6 : 0.3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        shimmer = true
                    }
                }

            Group {
                if let img = resolvedImage() {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(DemonicColor.backgroundCard)
                        Image(systemName: "music.note.list")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(DemonicGradient.titleGradient)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [DemonicColor.demonGreen.opacity(0.5), DemonicColor.demonPurple.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: DemonicColor.glowPurple, radius: 20)
            .shadow(color: DemonicColor.glowGreen.opacity(0.2), radius: 40)
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func resolvedImage() -> UIImage? {
        if let img = image { return img }
        if let data = imageData { return UIImage(data: data) }
        return nil
    }

    private func loadImage() async {
        guard let url else { imageData = nil; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run { imageData = data }
        } catch {
            await MainActor.run { imageData = nil }
        }
    }
}
