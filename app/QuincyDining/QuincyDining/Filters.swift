import Foundation
import Observation

/// Diet requirements and allergen exclusions, persisted across launches.
///
/// Deliberate wording throughout: this filters on what HUDS *declared*.
/// 180 of 411 archived recipes declare no allergens at all, and that silence
/// is missing data, not a clean bill of health. Nothing in this type or its
/// UI may describe a result as "safe".
@Observable
final class Filters {
    private enum Key {
        static let diets = "filters.diets"
        static let allergens = "filters.excludedAllergens"
    }

    // No didSet here on purpose. @Observable cannot apply its tracking
    // transformation to a property that has observers, so adding didSet
    // silently drops the property out of observation entirely and views
    // stop updating. Persist explicitly from the mutating methods instead.
    var requiredDiets: Set<DietTag> = []
    var excludedAllergens: Set<String> = []

    var isActive: Bool { !requiredDiets.isEmpty || !excludedAllergens.isEmpty }
    var count: Int { requiredDiets.count + excludedAllergens.count }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.stringArray(forKey: Key.diets) {
            requiredDiets = Set(raw.compactMap(DietTag.init(rawValue:)))
        }
        if let raw = defaults.stringArray(forKey: Key.allergens) {
            excludedAllergens = Set(raw)
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(requiredDiets.map(\.rawValue), forKey: Key.diets)
        defaults.set(Array(excludedAllergens), forKey: Key.allergens)
    }

    func setDiet(_ tag: DietTag, enabled: Bool) {
        if enabled { requiredDiets.insert(tag) } else { requiredDiets.remove(tag) }
        persist()
    }

    func setAllergen(_ allergen: String, excluded: Bool) {
        if excluded { excludedAllergens.insert(allergen) } else { excludedAllergens.remove(allergen) }
        persist()
    }

    func clear() {
        requiredDiets = []
        excludedAllergens = []
        persist()
    }

    /// An item passes when it carries every required diet tag and declares
    /// none of the excluded allergens.
    func allows(_ item: MenuItem) -> Bool {
        guard requiredDiets.isSubset(of: Set(item.dietTags)) else { return false }
        guard excludedAllergens.isDisjoint(with: Set(item.allergens)) else { return false }
        return true
    }

    /// Stations keep their order; any left empty by filtering are dropped.
    func apply(to meal: Meal) -> [Station] {
        guard isActive else { return meal.stations }
        return meal.stations.compactMap { station in
            let kept = station.items.filter(allows)
            guard !kept.isEmpty else { return nil }
            return Station(name: station.name, categoryId: station.categoryId, items: kept)
        }
    }
}
