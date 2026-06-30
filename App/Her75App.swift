import SwiftUI
import SwiftData

@main
struct Her75App: App {
    private let container = Persistence.shared

    var body: some Scene {
        WindowGroup {
            RootGate()
                .tint(Theme.rose)
        }
        .modelContainer(container)
    }
}

/// Gate the app on onboarding: no challenge yet → onboarding; otherwise the app.
/// Completing onboarding inserts the Challenge, which flips this automatically.
struct RootGate: View {
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]

    var body: some View {
        if challenges.isEmpty {
            OnboardingFlow()
                .transition(.opacity)
        } else {
            RootView()
                .transition(.opacity)
        }
    }
}
