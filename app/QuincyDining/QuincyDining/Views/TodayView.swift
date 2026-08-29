import SwiftUI

struct TodayView: View {
    @State private var store = MenuStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DateBar(store: store)
                mealPicker
                Divider()
                content
            }
            .navigationTitle("Quincy House")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
        .task {
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
                MealList(meal: meal, day: day, isStale: store.isStale, store: store)
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
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous day")

            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.headline)
                if !Calendar.current.isDateInToday(store.date) {
                    Text(store.dateKey).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()

            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next day")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(store.date) { return "Today" }
        if cal.isDateInTomorrow(store.date) { return "Tomorrow" }
        if cal.isDateInYesterday(store.date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: store.date)
    }

    private func step(_ days: Int) {
        store.shift(days: days)
        Task { await store.load() }
    }
}

private struct MealList: View {
    let meal: Meal
    let day: DayMenu
    let isStale: Bool
    let store: MenuStore

    var body: some View {
        List {
            ForEach(meal.stations) { station in
                Section {
                    ForEach(station.items) { item in
                        NavigationLink {
                            ItemDetailView(item: item, store: store)
                        } label: {
                            ItemRow(item: item)
                        }
                    }
                } header: {
                    Text(station.name).textCase(nil)
                }
            }

            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(meal.itemCount) items • as of \(day.fetchedAt.asFriendlyTimestamp)")
                    if isStale {
                        Label("Showing a saved copy — you're offline.",
                              systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                    }
                    Text("Menus are subject to change. Not affiliated with Harvard or HUDS.")
                        .font(.caption2)
                }
                .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
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
