import SwiftUI

/// Horizontal strip of the dates this hall has published. FoodPro publishes a
/// rolling 7-day window and keeps no history, so this shows exactly what
/// exists rather than an open calendar implying menus we cannot serve.
struct DateStrip: View {
    let store: MenuStore
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.availableDays, id: \.key) { day in
                        DayChip(key: day.key, serving: day.serving,
                                isSelected: day.key == store.dateKey)
                            .id(day.key)
                            .onTapGesture { onSelect(day.key) }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: store.dateKey) { _, key in
                withAnimation { proxy.scrollTo(key, anchor: .center) }
            }
            // The index arrives asynchronously, so onAppear alone fires against
            // an empty strip and the scroll is silently dropped.
            .onChange(of: store.availableDays.count) { _, n in
                if n > 0 { proxy.scrollTo(store.dateKey, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(store.dateKey, anchor: .center) }
        }
    }
}

private struct DayChip: View {
    let key: String
    let serving: Bool
    let isSelected: Bool
    private var date: Date? { MenuStore.dayFormatter.date(from: key) }

    var body: some View {
        VStack(spacing: 2) {
            Text(weekday).font(.caption2)
            Text(dayNumber).font(.headline)
            Circle().fill(serving ? .clear : Color.secondary).frame(width: 4, height: 4)
        }
        .frame(width: 46, height: 60)
        .foregroundStyle(isSelected ? .white : (serving ? .primary : .secondary))
        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isToday && !isSelected {
                RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }
    private var isToday: Bool { date.map { Calendar.current.isDateInToday($0) } ?? false }
    private var weekday: String {
        guard let date else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }
    private var dayNumber: String {
        guard let date else { return "" }
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }
}
