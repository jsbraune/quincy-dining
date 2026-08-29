import Foundation

/// Mirrors data/normalized/index.json
struct MenuIndex: Codable {
    let location: String
    let locationId: Int
    let generatedAt: String
    let servingDates: [String]
    let closedDates: [String]
    let recipeCount: Int
}

/// Mirrors data/normalized/quincy/YYYY-MM-DD.json
struct DayMenu: Codable {
    let date: String
    let fetchedAt: String
    let location: String
    let locationId: Int
    let itemCount: Int
    let meals: [Meal]

    func meal(_ kind: MealKind) -> Meal? {
        meals.first { $0.meal == kind.rawValue }
    }
}

struct Meal: Codable, Identifiable {
    let meal: String
    let stations: [Station]
    var id: String { meal }
    var kind: MealKind? { MealKind(rawValue: meal) }
    var itemCount: Int { stations.reduce(0) { $0 + $1.items.count } }
}

/// Station order is meaningful: it mirrors how the hall lays the meal out
/// (Soup, Salad Bar, Entrees, ...). Never sort these.
struct Station: Codable, Identifiable {
    let name: String
    let categoryId: Int
    let items: [MenuItem]
    var id: Int { categoryId }
}

struct MenuItem: Codable, Identifiable {
    let recipeId: Int
    let name: String
    let portion: String
    let tags: [String]
    let allergens: [String]
    let calories: Int?

    // Unique within a station; a recipe may legitimately appear in several
    // stations in one meal, so this is only stable inside its section.
    var id: Int { recipeId }

    var dietTags: [DietTag] { tags.compactMap(DietTag.init(rawValue:)) }
}

enum DietTag: String, CaseIterable, Identifiable {
    case vegan, vegetarian, halal
    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegan: return "Vegan"
        case .vegetarian: return "Vegetarian"
        case .halal: return "Halal"
        }
    }
}

enum MealKind: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner
    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    /// Which meal a student most likely wants to see right now. HUDS serves
    /// breakfast to ~10, lunch to ~2:15, dinner from 5; we bias late so that
    /// mid-afternoon shows dinner rather than a lunch that has ended.
    static func forNow(_ date: Date = Date(), calendar: Calendar = .current) -> MealKind {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case ..<11: return .breakfast
        case ..<15: return .lunch
        default: return .dinner
        }
    }
}
