import SwiftUI

/// Launch animation. Shown over the app, which loads behind it, so the
/// animation covers the first fetch instead of delaying it.
struct SplashView: View {
    @State private var plaqueIn = false
    @State private var titleIn = false

    static let crimson = Color(red: 165/255, green: 28/255, blue: 48/255)

    var body: some View {
        ZStack {
            Self.crimson.ignoresSafeArea()
            VStack(spacing: 28) {
                Image("HarvardShield")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 116)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 26)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    )
                    .scaleEffect(plaqueIn ? 1 : 0.94)
                    .opacity(plaqueIn ? 1 : 0)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("HARVARD")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(5)
                    Text("Dining")
                        .font(.system(size: 17))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .opacity(titleIn ? 1 : 0)
                .offset(y: titleIn ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { plaqueIn = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) { titleIn = true }
        }
    }
}

struct RootView: View {
    @State private var store = MenuStore()
    @State private var filters = Filters()
    @State private var showSplash = true

    var body: some View {
        ZStack {
            NavigationStack {
                if store.hall == nil {
                    HallPickerView(store: store)
                } else {
                    MenuView(store: store, filters: filters)
                }
            }
            if showSplash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
        .task {
            await store.loadIndex()
            if store.hall != nil { await store.load() }
            await store.loadRecipes()
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
        }
    }
}
