import Foundation
import Observation

/// Diet requirements and allergen exclusions, persisted across launches.
///
/// Filters match on what HUDS *declared*. Many items declare no allergens at
/// all, and that silence is missing data rather than a clean bill of health.
/// Nothing here or in its UI may describe a result as "safe".
@Observable
final class Filters {
    private enum Key {
        static let diets = "filters.diets"
        static let allergens = "filters.excludedAllergens"
    }

    // No didSet: @Observable cannot apply its tracking transformation to a
    // property with observers. Persist from the mutating methods instead.
    var requiredDiets: Set<DietTag> = []
    var excludedAllergens: Set<String> = []

    var isActive: Bool { !requiredDiets.isEmpty || !excludedAllergens.isEmpty }
    var count: Int { requiredDiets.count + excludedAllergens.count }

    init() {
        let d = UserDefaults.standard
        if let raw = d.stringArray(forKey: Key.diets) {
            requiredDiets = Set(raw.compactMap(DietTag.init(rawValue:)))
        }
        if let raw = d.stringArray(forKey: Key.allergens) { excludedAllergens = Set(raw) }
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(requiredDiets.map(\.rawValue), forKey: Key.diets)
        d.set(Array(excludedAllergens), forKey: Key.allergens)
    }

    func setDiet(_ tag: DietTag, enabled: Bool) {
        if enabled { requiredDiets.insert(tag) } else { requiredDiets.remove(tag) }
        persist()
    }

    func setAllergen(_ a: String, excluded: Bool) {
        if excluded { excludedAllergens.insert(a) } else { excludedAllergens.remove(a) }
        persist()
    }

    func clear() {
        requiredDiets = []
        excludedAllergens = []
        persist()
    }

    func allows(_ item: MenuItem) -> Bool {
        guard requiredDiets.isSubset(of: Set(item.dietTags)) else { return false }
        return excludedAllergens.isDisjoint(with: Set(item.allergens))
    }

    /// Stations keep their order; any emptied by filtering are dropped.
    func apply(to meal: Meal) -> [Station] {
        guard isActive else { return meal.stations }
        return meal.stations.compactMap { st in
            let kept = st.items.filter(allows)
            return kept.isEmpty ? nil : Station(name: st.name, items: kept)
        }
    }
}
