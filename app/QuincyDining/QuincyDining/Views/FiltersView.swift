import SwiftUI

struct FiltersView: View {
    let filters: Filters
    let knownAllergens: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Non-dismissable by design. Allergen filtering is the
                    // highest-liability feature in the app.
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Filtering hides items that **declare** an allergen. Harvard Dining cannot guarantee every allergen is identified, formulations change without notice, and cross-contact happens at self-service stations. Many items declare nothing at all. Never treat a filtered list as a list of safe foods — confirm with dining staff.")
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(DietTag.allCases) { tag in
                        // Read during body evaluation so @Observable registers
                        // the dependency. Reading inside the Binding's get
                        // closure instead runs after body and is not tracked,
                        // which leaves the Toggle permanently stuck off.
                        let isOn = filters.requiredDiets.contains(tag)
                        Toggle(isOn: Binding(
                            get: { isOn },
                            set: { filters.setDiet(tag, enabled: $0) }
                        )) {
                            Label(tag.label, systemImage: "leaf")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Show only").textCase(nil)
                } footer: {
                    Text("Items must carry every tag you select.")
                }

                Section {
                    ForEach(knownAllergens, id: \.self) { allergen in
                        let isOn = filters.excludedAllergens.contains(allergen)
                        Toggle(isOn: Binding(
                            get: { isOn },
                            set: { filters.setAllergen(allergen, excluded: $0) }
                        )) {
                            Text(allergen)
                        }
                    }
                } header: {
                    Text("Hide items declaring").textCase(nil)
                } footer: {
                    Text("Hides items whose published allergen list includes these. Items that declare no allergens are still shown.")
                }

                if filters.isActive {
                    Section {
                        Button("Clear all filters", role: .destructive) { filters.clear() }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

}
