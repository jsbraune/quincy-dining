import SwiftUI

struct ItemDetailView: View {
    let item: MenuItem
    let store: MenuStore

    private var detail: RecipeDetail? { store.recipes[item.recipeId] }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name).font(.title3.weight(.semibold))
                    if !item.portion.isEmpty {
                        Text("Serving size \(item.portion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !item.dietTags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(item.dietTags) { tag in
                                Text(tag.label)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(tag.color.opacity(0.15), in: Capsule())
                                    .foregroundStyle(tag.color)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            allergenSection
            nutritionSection
            ingredientsSection

            Section {
                Text("Menus are subject to change. Allergen and ingredient information comes from Harvard University Dining Services and cannot be guaranteed complete — manufacturers change formulations without notice, and cross-contact can occur, especially at self-service stations. If you have a food allergy, confirm with dining staff before eating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Unofficial app. Not affiliated with or endorsed by Harvard University or HUDS.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadRecipes() }
    }

    @ViewBuilder
    private var allergenSection: some View {
        Section {
            if item.allergens.isEmpty {
                Label {
                    Text("No allergens declared")
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                Text("This is the absence of a declaration, not a guarantee that the dish is free of allergens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(item.allergens, id: \.self) { allergen in
                    Label {
                        Text(allergen)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text("Allergens").textCase(nil)
        }
    }

    @ViewBuilder
    private var nutritionSection: some View {
        Section {
            if let detail, !detail.nutrition.isEmpty {
                ForEach(Nutrient.allCases) { nutrient in
                    if let value = detail.nutrition[nutrient.rawValue] {
                        HStack {
                            Text(nutrient.label)
                                .padding(.leading, nutrient.isSubEntry ? 16 : 0)
                                .foregroundStyle(nutrient.isSubEntry ? .secondary : .primary)
                            Spacer()
                            Text(nutrient.format(value))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } else if detail == nil {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else {
                Text("No nutrition information published for this item.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Nutrition").textCase(nil)
        } footer: {
            if let detail, !detail.nutrition.isEmpty, !item.portion.isEmpty {
                Text("Per \(item.portion) serving.")
            }
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        if let ingredients = detail?.ingredients, !ingredients.isEmpty {
            Section {
                Text(ingredients)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ingredients").textCase(nil)
            }
        }
        if let note = detail?.note, !note.isEmpty {
            Section {
                Text(note).font(.footnote)
            } header: {
                Text("Note").textCase(nil)
            }
        }
    }
}

extension DietTag {
    var color: Color {
        switch self {
        case .vegan: return .green
        case .vegetarian: return .teal
        case .halal: return .indigo
        }
    }
}
