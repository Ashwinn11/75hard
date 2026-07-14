import SwiftUI
import UIKit

// MARK: - Home-screen quick actions (the long-press menu on the app icon)
//
// The long-press menu doubles as a save: it's the same menu that shows "Remove App",
// so a non-subscriber about to delete sees our best price first. The deal row is
// dynamic — it only exists while the user isn't premium — and opens DealSheet.

@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()
    private init() {}

    enum Action: String {
        case logToday = "app.75her.com.action.log-today"
        case deal     = "app.75her.com.action.deal"
    }

    /// Set by the delegates below; consumed by the view layer (AppRoot / RootView).
    var pending: Action?

    @discardableResult
    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = Action(rawValue: item.type) else { return false }
        pending = action
        return true
    }

    /// Rebuild the menu from current state — called as the app backgrounds (the last
    /// write before a long-press can happen) and again when a purchase unlocks.
    /// One row each way, so the menu carries exactly one message: subscribers get the
    /// daily shortcut; everyone else gets only the deal.
    static func refresh() {
        UIApplication.shared.shortcutItems = Premium.shared.isPremium
            ? [UIApplicationShortcutItem(
                type: Action.logToday.rawValue,
                localizedTitle: "Log today",
                localizedSubtitle: "Check off today's tasks",
                icon: UIApplicationShortcutIcon(systemImageName: "checkmark.circle"))]
            : [UIApplicationShortcutItem(
                type: Action.deal.rawValue,
                localizedTitle: "Too expensive?",
                localizedSubtitle: dealSubtitle,
                icon: UIApplicationShortcutIcon(systemImageName: "gift"))]
    }

    /// States the actual offer ("Get 50% off the yearly plan") from the deal's computed
    /// badge. Falls back to a no-numbers line when the discount offering isn't live or
    /// hasn't loaded yet — never promise a percentage we can't honor.
    private static var dealSubtitle: String {
        if let badge = Premium.shared.deal?.badge {   // "50% OFF"
            return "Get \(badge.lowercased()) the yearly plan"
        }
        return "Save on the yearly plan"
    }
}

// A shortcut tap arrives through the scene delegate — cold launches in the connection
// options, warm launches via performActionFor — so the app delegate installs one.
// The delegate creates no windows; SwiftUI's WindowGroup stays in charge of the UI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.shared.handle(item)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.shared.handle(shortcutItem))
    }
}

// MARK: - Deal sheet ("Too expensive?" → the yearly plan, framed as the save)

/// A single-plan pitch: the "discount" offering's yearly price with its % OFF badge,
/// the regular yearly struck through above it. No plan list, no code to type — one button.
struct DealSheet: View {
    var onDone: () -> Void
    @State private var premium = Premium.shared
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "gift.fill").font(.system(size: 12, weight: .bold))
                Text("our best price").font(Font2.sans(12, .bold))
            }
            .foregroundStyle(Theme.berry)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.berry.opacity(0.12), in: Capsule())
            .padding(.top, 22)

            if premium.isPremium {
                Text("You're already all in")
                    .font(Font2.serif(28, .semibold)).foregroundStyle(Theme.ink)
                Text("Every day is unlocked on this account — nothing to buy.")
                    .font(Font2.sans(14, .medium)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Back to it") { onDone() }.padding(.top, 6)
            } else if let d = premium.deal {
                Text("Everything, for less")
                    .font(Font2.serif(28, .semibold)).foregroundStyle(Theme.ink)
                VStack(spacing: 3) {
                    if let anchor = premium.dealAnchor {
                        Text(anchor)
                            .font(Font2.sans(15, .bold))
                            .strikethrough(true, color: Theme.ink.opacity(0.5))
                            .foregroundStyle(Theme.ink.opacity(0.4))
                    }
                    HStack(spacing: 10) {
                        Text(d.price).font(Font2.sans(32, .heavy)).foregroundStyle(Theme.ink)
                        if let b = d.badge {
                            Text(b).font(Font2.sans(10, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.berry, in: Capsule())
                        }
                    }
                    Text("one payment — every challenge, all year")
                        .font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                        .padding(.top, 5)
                }
                PrimaryButton(title: busy ? "One sec…" : "Claim the yearly deal") { buy(d) }
                    .disabled(busy)
                    .padding(.top, 6)
                if let note {
                    Text(note).font(Font2.sans(12, .medium)).foregroundStyle(Theme.berryDeep)
                        .multilineTextAlignment(.center)
                }
                Text("Cancel anytime. Secure checkout")
                    .font(Font2.sans(11, .medium)).foregroundStyle(Theme.ink.opacity(0.35))
            } else if let err = premium.dealError {
                Text(err)
                    .font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).padding(.top, 8)
                Button {
                    Haptics.tap()
                    Task { await premium.loadDeal() }
                } label: {
                    Text("Try again").font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.chipFill, in: Capsule())
                }
            } else {
                ProgressView().tint(Theme.mauve).padding(.top, 10)
                Text("Fetching your deal…")
                    .font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .presentationDetents([.height(400)])
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.paper)
        .animation(Motion.gentle, value: premium.deal)
        .task { if premium.deal == nil { await premium.loadDeal() } }
    }

    private func buy(_ plan: Premium.Plan) {
        guard !busy else { return }
        busy = true; note = nil
        Task {
            do {
                if try await premium.purchase(plan) {
                    Haptics.success()
                    QuickActions.refresh()      // drop the deal row from the menu right away
                    onDone()
                }
            } catch {
                note = "The purchase didn't go through — you weren't charged. Try again."
            }
            busy = false
        }
    }
}
