import SwiftUI
import UIKit

enum Theme {
    static let accent = Color.accentColor

    // Map
    static let ocean = Color(light: 0xF7F4EF, dark: 0x1B1F27)
    static let land = Color(light: 0xE6E0D6, dark: 0x343A46)
    static let border = Color(light: 0xFFFFFF, dark: 0x1B1F27)
    static let home = Color(light: 0x7DB9F5, dark: 0x5EA3E8)
    /// Paint intensity by number of trips: 1, 2, 3+.
    static let visitRamp: [Color] = [
        Color(light: 0xFFCF9E, dark: 0xE7A86E),
        Color(light: 0xFB9374, dark: 0xF07F63),
        Color(light: 0xE9586E, dark: 0xE9586E),
    ]

    static func fill(tripCount: Int) -> Color {
        visitRamp[min(max(tripCount, 1), visitRamp.count) - 1]
    }

    static let progressGradient = AngularGradient(
        colors: [Color(hex: 0xFFCF9E), Color(hex: 0xFB9374), Color(hex: 0xE9586E), Color(hex: 0xFFCF9E)],
        center: .center)

    static let barGradient = LinearGradient(colors: [Color(hex: 0xFFCF9E), Color(hex: 0xE9586E)],
                                            startPoint: .leading, endPoint: .trailing)

    // Surfaces
    static let background = Color(light: 0xF7F4EF, dark: 0x14171D)
    static let card = Color(light: 0xFFFFFF, dark: 0x232831)
    static let placeholder = Color(light: 0xEDE8E1, dark: 0x2C323D)

    /// Deterministic soft gradient used as a cover when a trip has no photos.
    static func coverGradient(for key: String) -> LinearGradient {
        let palettes: [(UInt32, UInt32)] = [
            (0xFFCF9E, 0xE9586E), (0xA8E6CF, 0x3BAF8F), (0x8EC5FC, 0x6A7FDB),
            (0xF6D365, 0xFDA085), (0xD4A5F9, 0x8E6CDB), (0x96E6A1, 0x4FB0C6),
        ]
        let hash = key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let (a, b) = palettes[abs(hash) % palettes.count]
        return LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Formatting

enum Format {
    static let locale = Locale(identifier: "tr_TR")

    private static let intervalFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.locale = locale
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private static let shortIntervalFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// "12–15 Ağustos 2025"
    static func dateRange(_ start: Date, _ end: Date, short: Bool = false) -> String {
        (short ? shortIntervalFormatter : intervalFormatter).string(from: start, to: max(start, end))
    }

    /// "Ağustos 2025"
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    /// "%28" (Turkish puts the sign first)
    static func percent(_ fraction: Double) -> String {
        let value = fraction * 100
        let digits = value > 0 && value < 1 ? 1 : 0
        return "%" + value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    static func number(_ n: Int) -> String { n.formatted(.number.locale(locale)) }

    static func autoTitle(place: String, start: Date) -> String {
        "\(place) · \(monthYear(start))"
    }
}

extension String {
    /// Turkish-aware search key: "İstanbul", "istanbul" and "ISTANBUL" all match; "Muğla" matches "mugla".
    var searchKey: String {
        var s = self
        for (from, to) in [("İ", "i"), ("I", "i"), ("ı", "i")] { s = s.replacingOccurrences(of: from, with: to) }
        return s.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    func turkishCompare(_ other: String) -> ComparisonResult {
        compare(other, options: [.caseInsensitive], range: nil, locale: Format.locale)
    }
}
