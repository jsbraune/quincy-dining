import Foundation

/// One dining hall. Houses that share a kitchen have the same locationNum but
/// remain separate entries: they are separate dining halls, and which kitchen
/// cooks the food is back-of-house detail a student should never see.
struct Hall: Codable, Identifiable, Hashable {
    let hall: String
    let name: String
    let locationNum: String
    let servingDates: [String]
    let closedDates: [String]

    var id: String { hall }
    var shieldAsset: String { "Shield" + hall.prefix(1).uppercased() + hall.dropFirst() }
}

struct HallIndex: Codable {
    let generatedAt: String
    let halls: [Hall]
    let recipeCount: Int
}

struct DayMenu: Codable {
    let hall: String
    let hallName: String
    let locationNum: String
    let date: String
    let fetchedAt: String
    let itemCount: Int
    let meals: [Meal]

    func meal(_ kind: MealKind) -> Meal? { meals.first { $0.meal == kind.rawValue } }
}

struct Meal: Codable, Identifiable {
    let meal: String
    let stations: [Station]
    var id: String { meal }
    var kind: MealKind? { MealKind(rawValue: meal) }
    var itemCount: Int { stations.reduce(0) { $0 + $1.items.count } }
}

/// Station order mirrors how the hall lays the meal out. Never sort it.
struct Station: Codable, Identifiable {
    let name: String
    let items: [MenuItem]
    var id: String { name }
}

struct MenuItem: Codable, Identifiable {
    let name: String
    let recipeId: Int?
    let portion: String?
    let allergens: [String]
    let tags: [String]
    let calories: Int?

    // Names are unique within a station; a dish can appear in several stations.
    var id: String { name }
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

    /// Which meal to open on. Biased late so mid-afternoon shows dinner rather
    /// than a lunch that has already ended.
    static func forNow(_ date: Date = Date(), calendar: Calendar = .current) -> MealKind {
        switch calendar.component(.hour, from: date) {
        case ..<11: return .breakfast
        case ..<15: return .lunch
        default: return .dinner
        }
    }
}

struct RecipeDetail: Codable {
    let name: String
    let portion: String
    let allergens: [String]
    let ingredients: String?
    let nutrition: [String: Double]
    let vegan: Bool
    let vegetarian: Bool
    let note: String?
}

struct RecipeCatalog: Codable {
    let generatedAt: String
    let recipes: [String: RecipeDetail]
}

enum Nutrient: String, CaseIterable, Identifiable {
    case calories
    case total_fat_g, sat_fat_g, trans_fat_g
    case cholesterol_mg, sodium_mg
    case total_carb_g, dietary_fiber_g, sugars_g
    case protein_g
    var id: String { rawValue }

    var label: String {
        switch self {
        case .calories: return "Calories"
        case .total_fat_g: return "Total Fat"
        case .sat_fat_g: return "Saturated Fat"
        case .trans_fat_g: return "Trans Fat"
        case .cholesterol_mg: return "Cholesterol"
        case .sodium_mg: return "Sodium"
        case .total_carb_g: return "Total Carbohydrate"
        case .dietary_fiber_g: return "Dietary Fiber"
        case .sugars_g: return "Sugars"
        case .protein_g: return "Protein"
        }
    }
    var unit: String {
        switch self {
        case .calories: return ""
        case .cholesterol_mg, .sodium_mg: return "mg"
        default: return "g"
        }
    }
    var isSubEntry: Bool {
        switch self {
        case .sat_fat_g, .trans_fat_g, .dietary_fiber_g, .sugars_g: return true
        default: return false
        }
    }
    func format(_ v: Double) -> String {
        let n = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        return unit.isEmpty ? n : n + unit
    }
}
