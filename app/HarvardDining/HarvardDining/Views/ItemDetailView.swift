import SwiftUI

struct ItemDetailView: View {
    let item: MenuItem
    let store: MenuStore
    private var detail: RecipeDetail? { item.recipeId.flatMap { store.recipes[$0] } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name).font(.title3.weight(.semibold))
                    if let p = item.portion, !p.isEmpty {
                        Text("Serving size \(p)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !item.dietTags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(item.dietTags) { tag in
                                Text(tag.label)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(tag.color.opacity(0.15), in: Capsule())
                                    .foregroundStyle(tag.color)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if item.allergens.isEmpty {
                    Label { Text("No allergens declared") } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    Text("This is the absence of a declaration, not a guarantee.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(item.allergens, id: \.self) { a in
                        Label { Text(a) } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
            } header: { Text("Allergens").textCase(nil) }

            Section {
                if let detail, !detail.nutrition.isEmpty {
                    ForEach(Nutrient.allCases) { n in
                        if let v = detail.nutrition[n.rawValue] {
                            HStack {
                                Text(n.label)
                                    .padding(.leading, n.isSubEntry ? 16 : 0)
                                    .foregroundStyle(n.isSubEntry ? .secondary : .primary)
                                Spacer()
                                Text(n.format(v)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } else {
                    Text("No nutrition information published for this item.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } header: { Text("Nutrition").textCase(nil) }

            if let ing = detail?.ingredients, !ing.isEmpty {
                Section {
                    Text(ing).font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Ingredients").textCase(nil) }
            }

            Section {
                Text("Allergen and ingredient information comes from Harvard University Dining Services and can't be guaranteed complete. If you have a food allergy, check with dining staff before eating.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadRecipes() }
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
