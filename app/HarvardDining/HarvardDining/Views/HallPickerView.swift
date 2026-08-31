import SwiftUI

/// Choose a dining hall. Students recognise their House by its shield far
/// faster than they read a list, so the shield leads and the name labels it.
struct HallPickerView: View {
    let store: MenuStore

    // Fixed minimum rather than a fixed 3-column grid: at large Dynamic Type
    // a hardcoded column count overflows and clips the right-hand shields.
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: 10)]

    private var houses: [Hall] {
        (store.index?.halls ?? []).filter { !Self.nonHouse.contains($0.hall) }
    }
    private static let nonHouse: Set<String> = ["annenberg", "flyby", "bagmeals"]

    private func hall(_ slug: String) -> Hall? {
        store.index?.halls.first { $0.hall == slug }
    }

    var body: some View {
        ScrollView {
            if store.index == nil {
                ProgressView("Loading dining halls…").padding(.top, 60)
            } else {
                SectionLabel("HOUSES")
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(houses) { h in
                        Button { choose(h) } label: { HallCell(hall: h) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)

                if let ann = hall("annenberg") {
                    SectionLabel("FIRST-YEARS")
                    HallRow(title: ann.name, subtitle: "Memorial Hall",
                            asset: "HarvardShield") { choose(ann) }
                }

                SectionLabel("ALSO AVAILABLE")
                if let bag = hall("bagmeals") {
                    HallRow(title: "Bag Meals", subtitle: "Same selection campus-wide",
                            symbol: "takeoutbag.and.cup.and.straw") { choose(bag) }
                }
                if let fly = hall("flyby") {
                    HallRow(title: "FlyBy", subtitle: "Memorial Hall · grab-and-go",
                            symbol: "bolt.fill") { choose(fly) }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Choose a dining hall")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ h: Hall) {
        store.select(hall: h)
        Task { await store.load() }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

private struct HallCell: View {
    let hall: Hall

    var body: some View {
        VStack(spacing: 8) {
            Image(hall.shieldAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 58)
                .accessibilityHidden(true)
            Text(hall.name.replacingOccurrences(of: " House", with: ""))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hall.name)
    }
}

private struct HallRow: View {
    let title: String
    let subtitle: String
    var asset: String? = nil
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let asset {
                    Image(asset).resizable().scaledToFit().frame(height: 40)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .background(Color(.tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
