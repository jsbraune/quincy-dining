import Foundation
import Observation

/// Fetches normalized menu JSON published by the archiver, with an on-disk
/// fallback so the app still renders in a dining hall with no signal.
///
/// The server sets `cache-control: max-age=300` plus an ETag, so URLCache
/// handles revalidation; the disk copy exists for cold starts while offline.
@Observable
final class MenuStore {

    enum LoadState {
        case idle, loading
        case loaded(DayMenu)
        case closed(String)      // hall not serving on this date
        case failed(String)
    }

    private static let base = URL(string:
        "https://raw.githubusercontent.com/jsbraune/quincy-dining/main/data/normalized")!

    var state: LoadState = .idle
    var date: Date = MenuStore.initialDate()
    var selectedMeal: MealKind = .forNow()
    /// True when what is on screen came from disk rather than the network.
    var isStale = false

    private let session: URLSession
    private let cacheDir: URL

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("menus", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Lets a build be launched at a chosen date for verification:
    ///   xcrun simctl launch booted <bundle> --args -menuDate 2026-09-03
    static func initialDate() -> Date {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "menuDate"),
           let parsed = dayFormatter.date(from: raw) {
            return parsed
        }
        #endif
        return Date()
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var dateKey: String { Self.dayFormatter.string(from: date) }

    func load() async {
        let key = dateKey
        state = .loading
        isStale = false

        do {
            let data = try await fetch(path: "quincy/\(key).json")
            try? data.write(to: cacheDir.appendingPathComponent("\(key).json"))
            apply(data, key: key)
        } catch {
            // Network failed. Fall back to whatever we last saw for this date.
            let disk = cacheDir.appendingPathComponent("\(key).json")
            if let data = try? Data(contentsOf: disk) {
                isStale = true
                apply(data, key: key)
            } else if (error as NSError).code == 404 {
                state = .closed(key)
            } else {
                state = .failed(friendly(error))
            }
        }
    }

    private func apply(_ data: Data, key: String) {
        guard let day = try? JSONDecoder().decode(DayMenu.self, from: data) else {
            state = .failed("Could not read the menu for \(key).")
            return
        }
        if day.itemCount == 0 {
            state = .closed(key)
        } else {
            state = .loaded(day)
            // Keep the segmented control on a meal that actually has food.
            if day.meal(selectedMeal)?.itemCount ?? 0 == 0,
               let firstServed = MealKind.allCases.first(where: { (day.meal($0)?.itemCount ?? 0) > 0 }) {
                selectedMeal = firstServed
            }
        }
    }

    private func fetch(path: String) async throws -> Data {
        let (data, response) = try await session.data(from: Self.base.appendingPathComponent(path))
        guard let http = response as? HTTPURLResponse else { return data }
        guard http.statusCode == 200 else {
            throw NSError(domain: "MenuStore", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return data
    }

    private func friendly(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "No internet connection."
            case NSURLErrorTimedOut: return "The request timed out."
            default: return "Couldn't reach the menu server."
            }
        }
        return ns.localizedDescription
    }

    func shift(days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}

extension String {
    /// "2026-09-03T22:09:35-04:00" -> "Sep 3, 10:09 PM"
    var asFriendlyTimestamp: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let d = iso.date(from: self) else { return self }
        let out = DateFormatter()
        out.dateFormat = "MMM d, h:mm a"
        return out.string(from: d)
    }
}
