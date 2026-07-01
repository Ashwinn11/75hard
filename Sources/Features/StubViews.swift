import SwiftUI
import SwiftData

/// Friends tab — coming soon (the social backend is decided: CloudKit, see day/streak/completion;
/// build is parked). No fake data — just an honest preview of what's coming.
struct FriendsView: View {
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(day: challenge?.currentDay ?? 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        EyebrowLabel(text: "Accountability")
                        (Text("Follow your ").font(Font2.serif(34, .semibold)).foregroundColor(Theme.ink)
                         + Text("friends").font(Font2.serif(34, .semibold)).italic().foregroundColor(Theme.coral))
                    }

                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 44, weight: .light)).foregroundStyle(Theme.coral)
                        Text("Soon you'll add friends and see each other's day, streak, and completion — and cheer each other on through the challenge.")
                            .font(Font2.serif(19, .medium)).italic()
                            .foregroundStyle(Theme.ink.opacity(0.6)).multilineTextAlignment(.center)
                        HStack(spacing: 8) {
                            Image(systemName: "hammer.fill").font(.system(size: 12, weight: .bold))
                            Text("Coming soon").font(Font2.sans(13, .bold))
                        }
                        .foregroundStyle(Theme.ink.opacity(0.55))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.chipFill, in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .softCard()
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .her75Background()
    }
}
