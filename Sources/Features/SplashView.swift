import SwiftUI

/// Cold-launch splash: the app icon reveals on cream, holds a beat, then fades to the app.
/// The static launch screen (Info.plist → LaunchBackground) is the same cream, so there's no
/// flash before this — it just looks like the icon deliberately animating in.
struct SplashView: View {
    var onDone: () -> Void
    @State private var appear = false
    @State private var gone = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            Image("LaunchLogo")
                .resizable().scaledToFit()
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(Theme.ink.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 22, y: 12)
                .scaleEffect(appear ? 1 : 0.82)
                .opacity(appear ? 1 : 0)
        }
        .opacity(gone ? 0 : 1)
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.72)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.4)) { gone = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDone() }
            }
        }
    }
}

/// The window root: the app content with the launch splash on top until it dismisses itself.
/// Also hosts the quick-action deal sheet, so it can appear over any gate state
/// (onboarding, lapsed paywall, or the app proper).
struct AppRoot: View {
    @State private var showSplash = true
    @State private var quick = QuickActions.shared

    var body: some View {
        // Read `pending` in body (not just inside the Binding) so observation re-renders
        // this view when a shortcut lands and the sheet actually presents.
        let showDeal = quick.pending == .deal
        ZStack {
            RootGate()
            if showSplash {
                SplashView { showSplash = false }
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: Binding(get: { showDeal },
                                    set: { if !$0 { quick.pending = nil } })) {
            DealSheet { quick.pending = nil }
        }
    }
}
