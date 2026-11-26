import AVKit
import SwiftUI

/// Full-screen pager for a trip's photos and videos. Videos never autoplay and start muted.
struct MediaViewer: View {
    let items: [TripMedia]
    @State var selection: UUID
    @Environment(\.dismiss) private var dismiss

    init(items: [TripMedia], startID: UUID) {
        self.items = items
        _selection = State(initialValue: startID)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(items) { item in
                    Group {
                        if item.kind == .video, let id = item.assetIdentifier {
                            VideoPage(assetID: id)
                        } else {
                            ZoomablePhoto(media: item)
                        }
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Kapat")
                Spacer()
                if let current = items.first(where: { $0.id == selection }), let date = current.captureDate {
                    Text(Format.day(date))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding()
        }
    }
}

private struct ZoomablePhoto: View {
    let media: TripMedia
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            AssetImageView(assetID: media.assetIdentifier,
                           fallbackData: media.imageData ?? media.thumbnailData,
                           targetSize: CGSize(width: geo.size.width * 1.5, height: geo.size.height * 1.5),
                           contentMode: .fit)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, min(5, lastScale * $0.magnification)) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring) { scale = scale > 1 ? 1 : 2.5; lastScale = scale }
                }
        }
    }
}

private struct VideoPage: View {
    let assetID: String
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            guard player == nil, let asset = await PhotoLibrary.videoAsset(for: assetID) else { return }
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player.isMuted = true // the user can unmute from the controls
            self.player = player
        }
        .onDisappear { player?.pause() }
    }
}
