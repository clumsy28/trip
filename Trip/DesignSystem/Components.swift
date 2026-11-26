import SwiftUI
import UIKit

/// Shows a Photos library asset (or a stored fallback), filling its frame and clipping.
struct AssetImageView: View {
    let assetID: String?
    var fallbackData: Data?
    var targetSize = CGSize(width: 360, height: 360)
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var failed = false

    private var cacheKey: String? {
        assetID.map { "\($0)#\(Int(targetSize.width))x\(Int(targetSize.height))" }
    }

    var body: some View {
        Color.clear
            .overlay {
                if let shown = image ?? fallbackImage {
                    Image(uiImage: shown)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Theme.placeholder
                        .overlay {
                            if failed {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .clipped()
            .task(id: cacheKey) { await load() }
    }

    private var fallbackImage: UIImage? {
        fallbackData.flatMap(UIImage.init(data:))
    }

    private func load() async {
        guard let assetID, let key = cacheKey else { return }
        if let cached = ImageCache.shared.image(for: key) {
            image = cached
            return
        }
        guard PhotoLibrary.canRead else {
            failed = fallbackData == nil
            return
        }
        let scale = displayScale
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        if let loaded = await PhotoLibrary.image(for: assetID, targetSize: size,
                                                 contentMode: contentMode == .fill ? .aspectFill : .aspectFit) {
            ImageCache.shared.set(loaded, for: key)
            image = loaded
        } else {
            failed = fallbackData == nil
        }
    }
}

/// Thumbnail for a stored media item, with a video badge.
struct MediaThumbnail: View {
    let media: TripMedia
    var size: CGFloat = 120

    var body: some View {
        AssetImageView(assetID: media.assetIdentifier,
                       fallbackData: media.thumbnailData ?? media.imageData,
                       targetSize: CGSize(width: size, height: size))
            .overlay(alignment: .bottomLeading) {
                if media.kind == .video {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(5)
                        .shadow(radius: 2)
                }
            }
    }
}

/// A trip's cover photo, or a gradient with the place's initial.
struct TripCoverView: View {
    let trip: Trip
    var placeName: String
    var size: CGFloat = 400

    var body: some View {
        if let cover = trip.cover {
            MediaThumbnail(media: cover, size: size)
        } else {
            Theme.coverGradient(for: trip.regionRef?.key ?? trip.title)
                .overlay {
                    Text(String(placeName.prefix(1)))
                        .font(.system(size: 200, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.05)
                        .padding(size > 300 ? 40 : 14)
                        .foregroundStyle(.white.opacity(0.85))
                }
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Circular progress with the sunset gradient.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 14

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.placeholder, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, shown))
                .stroke(Theme.progressGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.spring(duration: 1.1)) { shown = fraction } }
        .onChange(of: fraction) { _, new in withAnimation(.spring(duration: 0.8)) { shown = new } }
    }
}

struct StatTile: View {
    let systemImage: String
    let value: String
    let label: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}
