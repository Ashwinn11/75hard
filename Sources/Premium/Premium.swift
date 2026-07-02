import Foundation
import Observation
import RevenueCat

private let revenueCatKey = "appl_QPTGxBXwEKhEldrWDvtUqgbyzAq"

// MARK: - Premium (RevenueCat)
//
// The app is premium-only: everything sits behind the "pro" entitlement on the default
// offering (weekly / monthly / yearly). `Premium.shared.status` drives two gates — the
// paywall as the last onboarding step, and RootGate, which swaps the whole app for the
// paywall if the subscription ever lapses.

@MainActor
@Observable
final class Premium {
    static let shared = Premium()

    enum Status: Equatable {
        case loading      // first CustomerInfo not in yet — let the app through, never flash a paywall
        case premium
        case locked
    }

    /// One subscription option, shaped for the paywall UI.
    struct Plan: Identifiable, Equatable {
        let id: String
        let title: String          // "Yearly"
        let price: String          // "$49.99/year"
        let badge: String?         // "SAVE 88%" — yearly vs 52 weekly renewals
        fileprivate let package: Package

        static func == (l: Self, r: Self) -> Bool {
            l.id == r.id && l.price == r.price && l.badge == r.badge
        }
    }

    private(set) var status: Status = .loading
    private(set) var plans: [Plan] = []
    private(set) var plansError: String?

    var isPremium: Bool { status == .premium }

    private init() {}

    /// Call once at launch, before the first view renders.
    nonisolated static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: revenueCatKey)
        Task { @MainActor in
            shared.watchCustomerInfo()
            await shared.loadPlans()
        }
    }

    /// Every CustomerInfo the SDK emits: launch cache, purchases, renewals, other devices.
    private func watchCustomerInfo() {
        Task {
            for await info in Purchases.shared.customerInfoStream {
                apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        status = info.entitlements["pro"]?.isActive == true ? .premium : .locked
    }

    // MARK: Plans

    func loadPlans() async {
        plansError = nil
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current ?? offerings.offering(identifier: "default") else {
                plans = []
                plansError = "Plans aren't set up yet. Check back in a moment."
                return
            }
            plans = Self.buildPlans(from: offering)
            if plans.isEmpty { plansError = "Plans aren't set up yet. Check back in a moment." }
        } catch {
            plans = []
            plansError = "Couldn't load plans. Check your connection and try again."
        }
    }

    /// Yearly → Monthly → Weekly. The yearly badge compares one year against 52 weekly renewals.
    private static func buildPlans(from offering: Offering) -> [Plan] {
        let yearly = offering.annual
        let monthly = offering.monthly
        let weekly = offering.weekly

        var badge: String?
        if let y = yearly?.storeProduct.price, let w = weekly?.storeProduct.price, w > 0 {
            let saved = 1 - (y as NSDecimalNumber).doubleValue / ((w as NSDecimalNumber).doubleValue * 52)
            let pct = Int((saved * 100).rounded())
            if pct >= 1 { badge = "SAVE \(pct)%" }
        }

        func plan(_ pkg: Package?, _ title: String, _ suffix: String, badge: String? = nil) -> Plan? {
            guard let pkg else { return nil }
            return Plan(id: pkg.identifier, title: title,
                        price: pkg.storeProduct.localizedPriceString + suffix,
                        badge: badge, package: pkg)
        }

        return [
            plan(yearly, "Yearly", "/year", badge: badge),
            plan(monthly, "Monthly", "/month"),
            plan(weekly, "Weekly", "/week"),
        ].compactMap { $0 }
    }

    // MARK: Purchase / restore

    /// True → the user is now premium. False → they backed out. Throws only on real failures.
    func purchase(_ plan: Plan) async throws -> Bool {
        do {
            let result = try await Purchases.shared.purchase(package: plan.package)
            apply(result.customerInfo)
            return !result.userCancelled && isPremium
        } catch ErrorCode.purchaseCancelledError {
            return false
        }
    }

    /// True → an active subscription came back for this Apple ID.
    func restore() async throws -> Bool {
        apply(try await Purchases.shared.restorePurchases())
        return isPremium
    }

    /// `restore()` folded into a user-facing outcome — shared by Settings and the paywall.
    /// `message` is nil when an active subscription came back.
    func restoreOutcome() async -> (restored: Bool, message: String?) {
        do {
            return try await restore()
                ? (true, nil)
                : (false, "No active subscription found on this Apple ID.")
        } catch {
            return (false, "Couldn't reach the App Store. Try again in a moment.")
        }
    }
}
