import Foundation
import Observation
import TripCore

enum AppTab: String, Hashable {
    case map, trips, stats, settings
}

/// A region that has just been painted; the map plays a short "pop" animation for it.
struct PaintEvent: Equatable {
    let ref: RegionRef
    let id = UUID()
}

/// App-wide UI state and lightweight preferences (persisted in UserDefaults).
@Observable
final class AppState {
    private enum Keys {
        static let pack = "trip.selectedPackID"
        static let home = "trip.homeRegionKey"
        static let includeHome = "trip.includeHomeInAutoImport"
        static let onboarded = "trip.hasCompletedOnboarding"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var selectedTab: AppTab = .map
    var isAutoImportPresented = false
    var paintEvent: PaintEvent?

    var selectedPackID: String {
        didSet { defaults.set(selectedPackID, forKey: Keys.pack) }
    }

    /// The user's home town ("memleket"), e.g. `turkey:TR-34`.
    var homeRegionKey: String? {
        didSet { defaults.set(homeRegionKey, forKey: Keys.home) }
    }

    var includeHomeInAutoImport: Bool {
        didSet { defaults.set(includeHomeInAutoImport, forKey: Keys.includeHome) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }

    var homeRegion: RegionRef? { homeRegionKey.flatMap(RegionRef.init(key:)) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedPackID = defaults.string(forKey: Keys.pack) ?? "turkey"
        homeRegionKey = defaults.string(forKey: Keys.home)
        includeHomeInAutoImport = defaults.bool(forKey: Keys.includeHome)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
    }

    func paint(_ ref: RegionRef) {
        paintEvent = PaintEvent(ref: ref)
    }
}

/// Debug/test launch arguments.
enum LaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// In-memory store, fresh preferences, no onboarding.
    static var isUITesting: Bool { arguments.contains("-uiTesting") }
    /// Fill the store with sample trips (DEBUG builds only).
    static var seedDemoData: Bool { arguments.contains("-seedDemoData") }
    static var initialTab: AppTab? { value(after: "-initialTab").flatMap(AppTab.init(rawValue:)) }
    static var initialPack: String? { value(after: "-initialPack") }

    #if DEBUG
    private static var openRegionConsumed = false
    private static var openTripConsumed = false

    /// `-openRegion turkey:TR-35` opens that region's sheet once (for screenshots).
    static func takeOpenRegion() -> RegionRef? {
        guard !openRegionConsumed else { return nil }
        openRegionConsumed = true
        return value(after: "-openRegion").flatMap(RegionRef.init(key:))
    }

    /// `-autoImport` opens the auto-import sheet and starts scanning right away.
    static var autoImport: Bool { arguments.contains("-autoImport") }
    private static var autoImportConsumed = false
    static func takeAutoImportStart() -> Bool {
        guard !autoImportConsumed else { return false }
        autoImportConsumed = true
        return autoImport
    }

    /// `-openTrip` pushes a sample trip's detail screen once (for screenshots).
    static func takeOpenTrip() -> Bool {
        guard !openTripConsumed else { return false }
        openTripConsumed = true
        return arguments.contains("-openTrip")
    }
    #endif

    private static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}
