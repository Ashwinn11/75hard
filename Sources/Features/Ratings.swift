import StoreKit
import UIKit

// MARK: - App Store rating prompts (one central gate)
//
// Views NOTE good moments; this decides whether to actually ask, so prompts ride real highs
// and the user is never nagged:
//   • value first — no ask before day 3 of a challenge (friend moments need one finished day)
//   • at most one ask every 30 days, three per rolling year (Apple also hard-caps at 3/365)
//   • finishing the whole challenge skips the 30-day wait, never the yearly cap
// requestReview is a request, not a command — Apple may still suppress the sheet.
@MainActor
enum Ratings {
    enum Moment {
        case dayComplete(day: Int)   // every mission checked off — fired as the celebration closes
        case friendJoined            // a friend request was accepted
        case challengeFinished       // crossed the finish line
    }

    static func note(_ moment: Moment) {
        switch moment {
        case .dayComplete(let day):
            bestDay = max(bestDay, day)
            guard day >= 3, cooledDown else { return }
        case .friendJoined:
            guard bestDay >= 1, cooledDown else { return }
        case .challengeFinished:
            guard yearCount < 3 else { return }
        }
        ask()
    }

    // MARK: Gate state (App Group, so a reinstall inside the cooldown stays quiet)

    private static var asks: [Date] {
        get { ((AppGroup.defaults.array(forKey: "ratingsAsks") as? [Double]) ?? []).map(Date.init(timeIntervalSince1970:)) }
        set { AppGroup.defaults.set(newValue.map(\.timeIntervalSince1970), forKey: "ratingsAsks") }
    }
    private static var bestDay: Int {
        get { AppGroup.defaults.integer(forKey: "ratingsBestDay") }
        set { AppGroup.defaults.set(newValue, forKey: "ratingsBestDay") }
    }
    private static var yearCount: Int {
        asks.filter { $0.timeIntervalSinceNow > -365 * 86_400 }.count
    }
    private static var cooledDown: Bool {
        guard yearCount < 3 else { return false }
        guard let last = asks.max() else { return true }
        return last.timeIntervalSinceNow < -30 * 86_400
    }

    /// Give the moment's own feedback (haptics, dismiss animation) a beat to land, then ask.
    private static func ask() {
        asks.append(Date())
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
        }
    }
}
