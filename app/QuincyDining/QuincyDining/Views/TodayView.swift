import SwiftUI

struct TodayView: View {
    @State private var store = MenuStore()
    @State private var filters = Filters()
    @State private var showingFilters = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DateBar(store: store)
                DateStrip(store: store) { key in
                    store.select(key)
                    Task { await store.load() }
                }
                .padding(.bottom, 10)
                mealPicker
                Divider()
                content
            }
            .navigationTitle("Quincy House")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilters = true } label: {
                        Image(systemName: filters.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(filters.isActive
                                        ? "Filters, \(filters.count) active"
                                        : "Filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(filters: filters, knownAllergens: store.knownAllergens)
            }
        }
        .task {
            await store.loadIndex()
            await store.load()
            await store.loadRecipes()
        }
    }

    @ViewBuilder
    private var mealPicker: some View {
        if case .loaded(let day) = store.state {
            // @Bindable, not an inline Binding: reads inside a closure are not
            // tracked as body dependencies under @Observable, so a programmatic
            // change to selectedMeal would leave the control visually stale.
            @Bindable var bindable = store
            Picker("Meal", selection: $bindable.selectedMeal) {
                ForEach(MealKind.allCases) { kind in
                    Text(kind.label)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .disabled(day.meals.isEmpty)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            LoadingView()
        case .failed(let message):
            MessageView(icon: "wifi.exclamationmark", title: "Couldn't load the menu",
                        detail: message, retry: { Task { await store.load() } })
        case .closed(let key):
            MessageView(icon: "moon.zzz", title: "Quincy isn't serving",
                        detail: "No meals published for \(friendlyDate(key)). The dining hall is closed or the menu hasn't been posted yet.",
                        retry: nil)
        case .loaded(let day):
            if let meal = day.meal(store.selectedMeal), meal.itemCount > 0 {
                MealList(meal: meal, day: day, isStale: store.isStale,
                         store: store, filters: filters)
            } else {
                MessageView(icon: "fork.knife", title: "No \(store.selectedMeal.label.lowercased()) service",
                            detail: "Quincy isn't serving \(store.selectedMeal.label.lowercased()) on this date.",
                            retry: nil)
            }
        }
    }

    private func friendlyDate(_ key: String) -> String {
        guard let d = MenuStore.dayFormatter.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: d)
    }
}

private struct DateBar: View {
    let store: MenuStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(longDate).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !Calendar.current.isDateInToday(store.date) {
                Button("Today") {
                    store.date = Date()
                    Task { await store.load() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(store.date) { return "Today" }
        if cal.isDateInTomorrow(store.date) { return "Tomorrow" }
        if cal.isDateInYesterday(store.date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: store.date)
    }

    private var longDate: String {
        let f = DateFormatter(); f.dateFormat = "MMMM d, yyyy"
        return f.string(from: store.date)
    }
}

private struct MealList: View {
    let meal: Meal
    let day: DayMenu
    let isStale: Bool
    let store: MenuStore
    let filters: Filters

    /// Explicit user overrides for this meal, keyed by category id. Empty at
    /// the start of every meal/day, so "default closed" stays literally true.
    @State private var expandedOverrides: [Int: Bool] = [:]

    private var stations: [Station] { filters.apply(to: meal) }
    private var shownCount: Int { stations.reduce(0) { $0 + $1.items.count } }

    /// The salad bar is the largest station and barely changes -- 27 of them
    /// across the archive resolve to just 5 distinct item sets -- so it starts
    /// closed at the meals where it is large. Breakfast is left open.
    private func startsCollapsed(_ station: Station) -> Bool {
        guard station.name == "Salad Bar" else { return false }
        return meal.kind == .lunch || meal.kind == .dinner
    }

    private func isExpanded(_ station: Station) -> Bool {
        expandedOverrides[station.categoryId] ?? !startsCollapsed(station)
    }

    var body: some View {
        List {
            if filters.isActive && stations.isEmpty {
                ContentUnavailableView(
                    "Nothing matches your filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No \(meal.meal) item matches. Try removing a filter.")
                )
            }
            ForEach(stations) { station in
                Section {
                    if isExpanded(station) {
                        ForEach(station.items) { item in
                            NavigationLink {
                                ItemDetailView(item: item, store: store)
                            } label: {
                                ItemRow(item: item)
                            }
                        }
                    }
                } header: {
                    StationHeader(
                        name: station.name,
                        count: station.items.count,
                        isExpanded: isExpanded(station)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedOverrides[station.categoryId] = !isExpanded(station)
                        }
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if filters.isActive {
                        Text("\(shownCount) of \(meal.itemCount) items shown • as of \(day.fetchedAt.asFriendlyTimestamp)")
                        Label("Filtered on declared allergens only. This is not a list of safe foods.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(meal.itemCount) items • as of \(day.fetchedAt.asFriendlyTimestamp)")
                    }
                    if isStale {
                        Label("Showing a saved copy — you're offline.",
                              systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                    }
                    Text("Menus are subject to change. Not affiliated with Harvard or HUDS.")
                        .font(.caption2)
                    Text("Harvard shield: public domain. Quincy House shield by Hstoops, CC BY-SA 4.0.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .id("\(day.date)-\(meal.meal)")
    }
}

/// Deliberately close to the plain text header it replaces: same type, same
/// placement, with a chevron and a count added only when it says something.
private struct StationHeader: View {
    let name: String
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(name).textCase(nil)
                if !isExpanded {
                    Text("(\(count))")
                        .textCase(nil)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed, \(count) items")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")
    }
}

private struct ItemRow: View {
    let item: MenuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.body)

            HStack(spacing: 6) {
                if !item.portion.isEmpty {
                    Text(item.portion)
                }
                if let cal = item.calories {
                    Text("• \(cal) cal")
                }
                ForEach(item.dietTags) { tag in
                    Text(tag.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tag.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(tag.color)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !item.allergens.isEmpty {
                Text("Contains: \(item.allergens.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack { Spacer(); ProgressView("Loading menu…"); Spacer() }
            .frame(maxWidth: .infinity)
    }
}

private struct MessageView: View {
    let icon: String
    let title: String
    let detail: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let retry {
                Button("Try Again", action: retry).buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
