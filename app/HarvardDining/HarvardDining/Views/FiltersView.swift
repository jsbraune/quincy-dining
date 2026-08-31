import SwiftUI

struct FiltersView: View {
    let filters: Filters
    let knownAllergens: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DietTag.allCases) { tag in
                        // Read during body evaluation so @Observable registers
                        // the dependency; reading inside the Binding's get
                        // closure is not tracked and the Toggle sticks.
                        let isOn = filters.requiredDiets.contains(tag)
                        Toggle(isOn: Binding(get: { isOn },
                                             set: { filters.setDiet(tag, enabled: $0) })) {
                            Text(tag.label)
                        }
                    }
                } header: {
                    Text("Show only").textCase(nil)
                } footer: {
                    Text("Items must carry every tag you select.")
                }

                Section {
                    ForEach(knownAllergens, id: \.self) { a in
                        let isOn = filters.excludedAllergens.contains(a)
                        Toggle(isOn: Binding(get: { isOn },
                                             set: { filters.setAllergen(a, excluded: $0) })) {
                            Text(a)
                        }
                    }
                } header: {
                    Text("Hide items declaring").textCase(nil)
                }

                if filters.isActive {
                    Section {
                        Button("Clear all filters", role: .destructive) { filters.clear() }
                    }
                }

                // One plain line at the bottom: tell people what the filter
                // actually matches on, rather than reciting a liability notice.
                Section {
                    Text("Filters match the allergens Harvard publishes. Many items don't list any, so check with dining staff if you have an allergy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
