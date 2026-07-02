import SwiftUI
import SwiftData

@main
struct Her75App: App {
    private let container = Persistence.shared

    init() {
        Premium.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootGate()
                .tint(Theme.rose)
        }
        .modelContainer(container)
    }
}

/// Two gates. Onboarding: no challenge yet → the flow (its last step is the paywall, so no one
/// gets in unpaid). Premium: the app is subscription-only, so a lapsed "pro" entitlement swaps
/// the whole app for the paywall until it's renewed or restored. `.loading` passes through —
/// never flash a paywall at cold launch while RevenueCat is still answering.
struct RootGate: View {
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var premium = Premium.shared

    var body: some View {
        if challenges.isEmpty {
            OnboardingFlow()
                .transition(.opacity)
        } else if premium.status == .locked {
            PaywallView(days: challenges.first?.lengthDays ?? 75, onUnlocked: {})
                .her75Background()
                .transition(.opacity)
        } else {
            RootView()
                .transition(.opacity)
        }
    }
}
