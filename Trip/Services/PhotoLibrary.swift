import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import TripCore
import UIKit

/// Thin, actor-agnostic wrapper around PhotoKit. Completion handlers fire on arbitrary threads, so nothing
/// here is main-actor isolated.
nonisolated enum PhotoLibrary {
    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    static var canRead: Bool { status == .authorized || status == .limited }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func sample(from asset: PHAsset) -> PhotoSample {
        PhotoSample(id: asset.localIdentifier,
                    date: asset.creationDate ?? .distantPast,
                    location: asset.location.map { GeoPoint(lon: $0.coordinate.longitude, lat: $0.coordinate.latitude) },
                    isVideo: asset.mediaType == .video)
    }

    /// Every photo/video that has both a date and a location, oldest first. Runs off the main actor.
    @concurrent
    static func locatedLibrarySamples(progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void) async -> (samples: [PhotoSample], scanned: Int) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        let total = result.count
        var samples: [PhotoSample] = []
        samples.reserveCapacity(total)
        for i in 0..<total {
            let asset = result.object(at: i)
            if asset.location != nil, asset.creationDate != nil {
                samples.append(sample(from: asset))
            }
            if i % 200 == 0 { progress(i, total) }
        }
        progress(total, total)
        return (samples, total)
    }

    static func image(for id: String, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        guard let asset = asset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // exactly one callback
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: contentMode,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    static func thumbnailData(for id: String) async -> Data? {
        await image(for: id, targetSize: CGSize(width: 360, height: 360))?.jpegData(compressionQuality: 0.75)
    }

    static func videoAsset(for id: String) async -> AVAsset? {
        guard let asset = asset(id) else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let box: AVAssetBox = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: AVAssetBox(asset: avAsset))
            }
        }
        return box.asset
    }

    private struct AVAssetBox: @unchecked Sendable { let asset: AVAsset? }
}

/// A picked/attached media item before it becomes a `TripMedia`.
struct ImportedMedia: Identifiable, Hashable {
    let id = UUID()
    var assetID: String?
    var kind: MediaKind
    var date: Date?
    var location: GeoPoint?
    var imageData: Data?

    var sample: PhotoSample? {
        guard let date else { return nil }
        return PhotoSample(id: assetID ?? id.uuidString, date: date, location: location, isVideo: kind == .video)
    }
}

enum MediaImporter {
    /// Converts picker selections into importable media: a library reference when possible, otherwise
    /// a downscaled copy of the image (e.g. when the user only granted limited access).
    static func importItems(_ items: [PhotosPickerItem]) async -> [ImportedMedia] {
        var result: [ImportedMedia] = []
        for item in items {
            if let id = item.itemIdentifier, let asset = PhotoLibrary.asset(id) {
                let sample = PhotoLibrary.sample(from: asset)
                result.append(ImportedMedia(assetID: id, kind: sample.isVideo ? .video : .photo,
                                            date: asset.creationDate, location: sample.location))
                continue
            }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            guard !isVideo,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let copy = image.downscaled(maxPixel: 2048).jpegData(compressionQuality: 0.85) else { continue }
            result.append(ImportedMedia(assetID: nil, kind: .photo, date: nil, location: nil, imageData: copy))
        }
        return result
    }

    static func media(from samples: [PhotoSample]) -> [ImportedMedia] {
        samples.map { ImportedMedia(assetID: $0.id, kind: $0.isVideo ? .video : .photo, date: $0.date, location: $0.location) }
    }

    /// Adds media to a trip, skipping library assets that are already attached. Returns the new records.
    @discardableResult
    static func attach(_ items: [ImportedMedia], to trip: Trip) -> [TripMedia] {
        var existing = Set((trip.media ?? []).compactMap(\.assetIdentifier))
        var added: [TripMedia] = []
        for item in items {
            if let id = item.assetID {
                guard !existing.contains(id) else { continue }
                existing.insert(id)
            }
            let media = TripMedia(assetIdentifier: item.assetID, kind: item.kind, captureDate: item.date,
                                  location: item.location, imageData: item.imageData)
            if let data = item.imageData {
                media.thumbnailData = UIImage(data: data)?.downscaled(maxPixel: 360).jpegData(compressionQuality: 0.75)
            }
            media.trip = trip
            trip.media = (trip.media ?? []) + [media]
            added.append(media)
        }
        return added
    }

    /// Fills in cached thumbnails so trips keep a preview even if the original leaves the library.
    static func backfillThumbnails(_ media: [TripMedia]) async {
        for item in media where item.thumbnailData == nil {
            guard let id = item.assetIdentifier else { continue }
            if let data = await PhotoLibrary.thumbnailData(for: id) {
                item.thumbnailData = data
            }
        }
    }
}

extension UIImage {
    func downscaled(maxPixel: CGFloat) -> UIImage {
        let longest = max(size.width, size.height) * scale
        guard longest > maxPixel else { return self }
        let factor = maxPixel / longest
        let newSize = CGSize(width: size.width * scale * factor, height: size.height * scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Small in-memory cache so grids don't re-request the same thumbnails while scrolling.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 400 }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}
