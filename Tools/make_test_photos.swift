// Generates JPEGs with GPS + capture date EXIF to exercise photo auto-import in the simulator.
// Usage:
//   swift Tools/make_test_photos.swift /tmp/trip-photos
//   xcrun simctl addmedia booted /tmp/trip-photos/*.jpg
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Shot {
    let name: String
    let lat: Double
    let lon: Double
    let date: String // "yyyy:MM:dd HH:mm:ss"
    let color: (CGFloat, CGFloat, CGFloat)
}

func series(_ name: String, lat: Double, lon: Double, start: String, count: Int, everyHours: Double,
            color: (CGFloat, CGFloat, CGFloat)) -> [Shot] {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Istanbul")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    let out = DateFormatter()
    out.locale = f.locale
    out.timeZone = f.timeZone
    out.dateFormat = "yyyy:MM:dd HH:mm:ss"
    let base = f.date(from: start)!
    return (0..<count).map { i in
        let d = base.addingTimeInterval(Double(i) * everyHours * 3600)
        // Jitter the position a little, like photos taken around town.
        let jitter = Double(i % 5) * 0.004
        return Shot(name: "\(name)-\(i)", lat: lat + jitter, lon: lon - jitter, date: out.string(from: d), color: color)
    }
}

let shots: [Shot] =
    series("izmir-2025", lat: 38.4237, lon: 27.1428, start: "2025-08-12 10:00", count: 8, everyHours: 7, color: (0.98, 0.58, 0.45))
    + series("izmir-2024", lat: 37.9440, lon: 27.4300, start: "2024-04-20 11:00", count: 4, everyHours: 5, color: (0.95, 0.75, 0.40))
    + series("antalya", lat: 36.8860, lon: 30.7030, start: "2024-07-03 09:00", count: 5, everyHours: 20, color: (0.35, 0.70, 0.85))
    + series("nevsehir-pass", lat: 38.6250, lon: 34.7120, start: "2024-07-08 15:00", count: 2, everyHours: 1, color: (0.60, 0.60, 0.60))
    + series("paris", lat: 48.8584, lon: 2.2945, start: "2024-09-05 12:00", count: 6, everyHours: 16, color: (0.55, 0.45, 0.85))
    + series("istanbul-home", lat: 41.0082, lon: 28.9784, start: "2025-01-01 18:00", count: 30, everyHours: 36, color: (0.45, 0.65, 0.95))

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "trip-test-photos")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
for shot in shots {
    let w = 600, h = 450
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let (r, g, b) = shot.color
    ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
    ctx.fillEllipse(in: CGRect(x: 380, y: 260, width: 140, height: 140)) // "sun"
    ctx.setFillColor(CGColor(srgbRed: r * 0.6, green: g * 0.6, blue: b * 0.6, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: 140)) // "ground"

    let url = dir.appendingPathComponent("\(shot.name).jpg")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let gps: [CFString: Any] = [
        kCGImagePropertyGPSLatitude: abs(shot.lat),
        kCGImagePropertyGPSLatitudeRef: shot.lat >= 0 ? "N" : "S",
        kCGImagePropertyGPSLongitude: abs(shot.lon),
        kCGImagePropertyGPSLongitudeRef: shot.lon >= 0 ? "E" : "W",
    ]
    let exif: [CFString: Any] = [
        kCGImagePropertyExifDateTimeOriginal: shot.date,
        kCGImagePropertyExifDateTimeDigitized: shot.date,
        kCGImagePropertyExifOffsetTimeOriginal: "+03:00",
    ]
    let props: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: gps,
        kCGImagePropertyExifDictionary: exif,
        kCGImageDestinationLossyCompressionQuality: 0.8,
    ]
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest))
}
print("✓ wrote \(shots.count) photos to \(dir.path)")
