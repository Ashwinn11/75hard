import SwiftUI

/// Native SwiftUI tab bar — no custom reinvention.
struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.rose)
    }
}
