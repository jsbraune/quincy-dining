import SwiftUI

/// Launch animation. Shown over the menu, which is already loading behind it,
/// so the animation covers the first fetch instead of delaying it.
struct SplashView: View {
    @State private var shieldsIn = false
    @State private var titleIn = false
    @State private var separatorWidth: CGFloat = 0

    private static let crimson = Color(red: 165/255, green: 28/255, blue: 48/255)

    var body: some View {
        ZStack {
            Self.crimson.ignoresSafeArea()

            VStack(spacing: 28) {
                // The Quincy arms are gules -- the same crimson as the
                // background -- so on bare crimson the shield dissolves and
                // only its gold mascles read. Both marks sit on a white
                // plaque so each one keeps its shape.
                HStack(spacing: 22) {
                    shield("HarvardShield", delay: 0)
                    Rectangle()
                        .fill(Self.crimson.opacity(0.25))
                        .frame(width: 1, height: separatorWidth)
                    shield("QuincyShield", delay: 0.12)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                )
                .scaleEffect(shieldsIn ? 1 : 0.94)
                .opacity(shieldsIn ? 1 : 0)

                VStack(spacing: 6) {
                    Text("QUINCY HOUSE")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(4)
                    Text("Dining")
                        .font(.system(size: 17, weight: .regular))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .opacity(titleIn ? 1 : 0)
                .offset(y: titleIn ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                shieldsIn = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                separatorWidth = 88
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
                titleIn = true
            }
        }
    }

    private func shield(_ name: String, delay: Double) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 108)
            .accessibilityHidden(true)
    }
}

/// Holds the splash over the menu for a beat, then crossfades.
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TodayView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
        }
    }
}
