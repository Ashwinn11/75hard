import SwiftUI

/// Native SwiftUI tab bar — no custom reinvention.
struct RootView: View {
    @State private var celebration = CelebrationCenter()

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.ink)
        .environment(celebration)
        .blur(radius: celebration.day != nil ? 22 : 0)
        .overlay {
            if let day = celebration.day {
                DayCelebration(day: day) { celebration.day = nil }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: celebration.day)
        // Ask for a rating as the day-complete celebration closes — riding the high without
        // covering the confetti. The Ratings gate decides if it's actually time to ask.
        .onChange(of: celebration.day) { old, new in
            if new == nil, let old {
                Ratings.note(celebration.finale ? .challengeFinished : .dayComplete(day: old))
            }
        }
    }
}
