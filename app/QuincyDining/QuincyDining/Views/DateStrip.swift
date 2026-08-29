import SwiftUI

/// Horizontal strip of every published date. The upstream feed publishes a
/// rolling window of roughly two weeks and keeps no history, so this shows
/// exactly what exists rather than an open-ended calendar that would imply
/// menus we cannot serve.
struct DateStrip: View {
    let store: MenuStore
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.availableDays, id: \.key) { day in
                        DayChip(
                            key: day.key,
                            serving: day.serving,
                            isSelected: day.key == store.dateKey
                        )
                        .id(day.key)
                        .onTapGesture { onSelect(day.key) }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: store.dateKey) { _, key in
                withAnimation { proxy.scrollTo(key, anchor: .center) }
            }
            // The index arrives asynchronously, so onAppear alone fires while
            // the strip is still empty and the scroll is silently dropped.
            .onChange(of: store.availableDays.count) { _, count in
                guard count > 0 else { return }
                proxy.scrollTo(store.dateKey, anchor: .center)
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
            // A closed day is shown, not hidden -- "the hall is shut" is
            // information the student needs, and hiding it looks like a bug.
            Circle()
                .fill(serving ? Color.clear : Color.secondary)
                .frame(width: 4, height: 4)
        }
        .frame(width: 46, height: 60)
        .foregroundStyle(foreground)
        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isToday && !isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    private var foreground: Color {
        if isSelected { return .white }
        return serving ? .primary : .secondary
    }

    private var isToday: Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var weekday: String {
        guard let date else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private var dayNumber: String {
        guard let date else { return "" }
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }
}
