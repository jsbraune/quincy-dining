import SwiftUI

struct MenuView: View {
    let store: MenuStore
    let filters: Filters
    @State private var showingFilters = false

    var body: some View {
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
        .navigationTitle(store.hall?.name ?? "Menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.hall = nil } label: {
                    Label("Halls", systemImage: "square.grid.2x2")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingFilters = true } label: {
                    Image(systemName: filters.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(filters.isActive ? "Filters, \(filters.count) active" : "Filters")
            }
        }
        .sheet(isPresented: $showingFilters) {
            FiltersView(filters: filters, knownAllergens: store.knownAllergens)
        }
    }

    @ViewBuilder
    private var mealPicker: some View {
        if case .loaded = store.state {
            @Bindable var bindable = store
            Picker("Meal", selection: $bindable.selectedMeal) {
                ForEach(MealKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            VStack { Spacer(); ProgressView("Loading menu…"); Spacer() }
                .frame(maxWidth: .infinity)
        case .failed(let message):
            MessageView(icon: "wifi.exclamationmark", title: "Couldn't load the menu",
                        detail: message) { Task { await store.load() } }
        case .closed(let key):
            MessageView(icon: "moon.zzz", title: "Not serving",
                        detail: "No meals published for \(friendly(key)).", retry: nil)
        case .loaded(let day):
            if let meal = day.meal(store.selectedMeal), meal.itemCount > 0 {
                MealList(meal: meal, day: day, store: store, filters: filters)
            } else {
                MessageView(icon: "fork.knife",
                            title: "No \(store.selectedMeal.label.lowercased()) service",
                            detail: "\(day.hallName) isn't serving \(store.selectedMeal.label.lowercased()) on this date.",
                            retry: nil)
            }
        }
    }

    private func friendly(_ key: String) -> String {
        guard let d = MenuStore.dayFormatter.date(from: key) else { return key }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
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
        let c = Calendar.current
        if c.isDateInToday(store.date) { return "Today" }
        if c.isDateInTomorrow(store.date) { return "Tomorrow" }
        if c.isDateInYesterday(store.date) { return "Yesterday" }
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
    let store: MenuStore
    let filters: Filters
    @State private var expandedOverrides: [String: Bool] = [:]

    private var stations: [Station] { filters.apply(to: meal) }
    private var shownCount: Int { stations.reduce(0) { $0 + $1.items.count } }

    /// The salad bar is the largest station and barely changes day to day, so
    /// it starts closed where it is large. Breakfast keeps it open.
    private func startsCollapsed(_ s: Station) -> Bool {
        s.name == "Salad Bar" && (meal.kind == .lunch || meal.kind == .dinner)
    }
    private func isExpanded(_ s: Station) -> Bool {
        expandedOverrides[s.name] ?? !startsCollapsed(s)
    }

    var body: some View {
        List {
            if filters.isActive && stations.isEmpty {
                ContentUnavailableView("Nothing matches your filters",
                                       systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Try removing a filter."))
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
                    StationHeader(name: station.name, count: station.items.count,
                                  isExpanded: isExpanded(station)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedOverrides[station.name] = !isExpanded(station)
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
                    } else {
                        Text("\(meal.itemCount) items • as of \(day.fetchedAt.asFriendlyTimestamp)")
                    }
                    if store.isStale {
                        Label("Showing a saved copy — you're offline.",
                              systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                    }
                    Text("Menus are subject to change. Unofficial app, not affiliated with Harvard or HUDS.")
                        .font(.caption2)
                    Text("House shields via Wikimedia Commons, CC BY-SA 4.0.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .id("\(day.hall)-\(day.date)-\(meal.meal)")
    }
}

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
                    Text("(\(count))").textCase(nil).foregroundStyle(.tertiary)
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
    }
}

private struct ItemRow: View {
    let item: MenuItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.body)
            HStack(spacing: 6) {
                if let p = item.portion, !p.isEmpty { Text(p) }
                if let cal = item.calories { Text("• \(cal) cal") }
                ForEach(item.dietTags) { tag in
                    Text(tag.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tag.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(tag.color)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !item.allergens.isEmpty {
                Text("Contains: \(item.allergens.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MessageView: View {
    let icon: String
    let title: String
    let detail: String
    let retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if let retry { Button("Try Again", action: retry).buttonStyle(.bordered) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
