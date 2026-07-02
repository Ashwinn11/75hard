import SwiftUI

/// Native SwiftUI tab bar — no custom reinvention.
struct RootView: View {
    @State private var celebration = CelebrationCenter()
    @State private var tab = Tab.today

    enum Tab: Hashable { case today, friends, profile }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
                .tag(Tab.today)
            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(Tab.friends)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .tint(Theme.ink)
        .environment(celebration)
        .sensoryFeedback(.selection, trigger: tab)
        // The app pushes back in depth while the celebration takes the stage.
        .blur(radius: celebration.day != nil ? 22 : 0)
        .scaleEffect(celebration.day != nil ? 0.96 : 1)
        .overlay {
            if let day = celebration.day {
                DayCelebration(day: day) { celebration.day = nil }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(Motion.gentle, value: celebration.day)
        // Ask for a rating as the day-complete celebration closes — riding the high without
        // covering the confetti. The Ratings gate decides if it's actually time to ask.
        .onChange(of: celebration.day) { old, new in
            if new == nil, let old {
                Ratings.note(celebration.finale ? .challengeFinished : .dayComplete(day: old))
            }
        }
    }
}
