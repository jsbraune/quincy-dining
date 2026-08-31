import Foundation
import Observation

/// Fetches normalized menus published by the hall archiver, with an on-disk
/// fallback so the app still renders in a dining hall with no signal.
@Observable
final class MenuStore {

    enum LoadState {
        case idle, loading
        case loaded(DayMenu)
        case closed(String)
        case failed(String)
    }

    private static let base = URL(string:
        "https://raw.githubusercontent.com/jsbraune/quincy-dining/main/data/normalized/halls")!

    /// The hall being viewed. Persisted so the app opens where it left off.
    // No didSet: property observers interact badly with @Observable's
    // tracking transformation. Persist explicitly via select(hall:).
    var hall: Hall?
    var index: HallIndex?
    var state: LoadState = .idle
    var date: Date = MenuStore.initialDate()
    var selectedMeal: MealKind = MenuStore.initialMeal()
    var recipes: [Int: RecipeDetail] = [:]
    var isStale = false

    private let session: URLSession
    private let cacheDir: URL

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 96 << 20)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("halls", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Debug-only launch overrides, so a build can be driven straight to a
    /// given hall/date/meal without tapping:
    ///   --args -menuHall adams -menuDate 2026-09-04 -menuMeal dinner
    static func initialDate() -> Date {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "menuDate"),
           let d = dayFormatter.date(from: raw) { return d }
        #endif
        return Date()
    }

    static func initialMeal() -> MealKind {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "menuMeal"),
           let k = MealKind(rawValue: raw.lowercased()) { return k }
        #endif
        return .forNow()
    }

    var dateKey: String { Self.dayFormatter.string(from: date) }

    func loadIndex() async {
        let disk = cacheDir.appendingPathComponent("index.json")
        var data = try? await fetch("index.json")
        if let fresh = data { try? fresh.write(to: disk) } else { data = try? Data(contentsOf: disk) }
        guard let data, let decoded = try? JSONDecoder().decode(HallIndex.self, from: data) else { return }
        index = decoded
        if hall == nil {
            #if DEBUG
            let forced = UserDefaults.standard.string(forKey: "menuHall")
            #else
            let forced: String? = nil
            #endif
            let wanted = forced ?? UserDefaults.standard.string(forKey: "lastHall")
            hall = decoded.halls.first { $0.hall == wanted }
        }
    }

    func load() async {
        guard let hall else { return }
        let key = dateKey
        state = .loading
        isStale = false
        let path = "\(hall.hall)/\(key).json"
        let diskName = "\(hall.hall)-\(key).json"
        do {
            let data = try await fetch(path)
            try? data.write(to: cacheDir.appendingPathComponent(diskName))
            apply(data, key: key)
        } catch {
            if let data = try? Data(contentsOf: cacheDir.appendingPathComponent(diskName)) {
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
            // Keep the picker on a meal that is actually served -- halls
            // routinely skip a meal (Quincy posts no dinner some days).
            if (day.meal(selectedMeal)?.itemCount ?? 0) == 0,
               let served = MealKind.allCases.first(where: { (day.meal($0)?.itemCount ?? 0) > 0 }) {
                selectedMeal = served
            }
        }
    }

    func loadRecipes() async {
        guard recipes.isEmpty else { return }
        let disk = cacheDir.appendingPathComponent("recipes.json")
        var data = try? await fetch("recipes.json")
        if let fresh = data { try? fresh.write(to: disk) } else { data = try? Data(contentsOf: disk) }
        guard let data, let cat = try? JSONDecoder().decode(RecipeCatalog.self, from: data) else { return }
        var byId: [Int: RecipeDetail] = [:]
        for (k, v) in cat.recipes { if let id = Int(k) { byId[id] = v } }
        recipes = byId
    }

    private func fetch(_ path: String) async throws -> Data {
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

    /// Every date this hall has published, with whether it is serving.
    var availableDays: [(key: String, serving: Bool)] {
        guard let hall else { return [] }
        let serving = Set(hall.servingDates)
        return (hall.servingDates + hall.closedDates).sorted().map { ($0, serving.contains($0)) }
    }

    func select(hall newHall: Hall) {
        hall = newHall
        UserDefaults.standard.set(newHall.hall, forKey: "lastHall")
    }

    func select(_ key: String) {
        if let d = Self.dayFormatter.date(from: key) { date = d }
    }

    var knownAllergens: [String] { Set(recipes.values.flatMap(\.allergens)).sorted() }
}

extension String {
    var asFriendlyTimestamp: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let d = iso.date(from: self) else { return self }
        let out = DateFormatter()
        out.dateFormat = "MMM d, h:mm a"
        return out.string(from: d)
    }
}
