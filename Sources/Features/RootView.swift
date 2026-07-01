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
        .tint(Theme.rose)
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
    }
}
