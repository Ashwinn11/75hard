import SwiftUI

/// The real paywall — plans stream from RevenueCat's default offering. Premium-only app, so
/// there is no close button: this is the last onboarding step, and RootGate shows it full-screen
/// if the subscription ever lapses.
struct PaywallView: View {
    var days: Int = 75
    var onUnlocked: () -> Void
    /// Onboarding passes this so Close returns to the plan preview (state persists in the
    /// OnboardingModel). RootGate leaves it nil — a lapsed subscriber can't dismiss into the app.
    var onClose: (() -> Void)? = nil

    @State private var premium = Premium.shared
    @State private var selectedID: String?
    @State private var busy = false
    @State private var notice: Notice?
    @State private var legal: LegalView.Kind?
    @State private var didUnlock = false
    @State private var ctaFlip = false      // alternates the CTA vision ↔ price

    /// Cycles the CTA between the aspirational line and the (Apple-required) price + period.
    private let ctaTimer = Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()

    /// A one-off alert for a purchase / restore outcome (shown, tapped away, gone).
    private struct Notice: Identifiable { let id = UUID(); let title: String; let message: String }

    private var selected: Premium.Plan? {
        premium.plans.first { $0.id == selectedID } ?? premium.plans.first
    }

    /// Sell the vision, then disclose the price — the button crossfades between the two.
    /// Price + period ride along in `Plan.price` ("$4.99/week"), and the plan rows show it
    /// persistently too, so the alternating button stays App Store compliant.
    private var ctaTitle: String {
        if busy { return "One sec…" }
        guard let p = selected else { return "Start the journey" }
        return ctaFlip ? "Start for \(p.price)" : "I'm all in"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero — vertically centered in the space above the footer.
            VStack(spacing: 20) {
                SocialProofCluster()
                VStack(spacing: 2) {
                    Text("All \(days) days. All in.")
                        .font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                    Text("Every feature, from day one")
                        .font(Font2.serif(26, .semibold)).foregroundStyle(Theme.ink)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Every challenge, fully unlocked",
                             "Daily tracking, photos & streaks",
                             "Friends who keep you showing up",
                             "Widgets & gentle reminders"], id: \.self) { b in
                        Label(b, systemImage: "checkmark.circle.fill")
                            .font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 30)

            // Footer — plans + CTA anchored at the bottom.
            VStack(spacing: 14) {
                plansSection.padding(.horizontal, 22)
                ctaPad(VStack(spacing: 10) {
                    PrimaryButton(title: ctaTitle) { buy() }
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.45), value: ctaTitle)
                        .onReceive(ctaTimer) { _ in if !busy { ctaFlip.toggle() } }
                        .shimmerOnce(delay: 0.8)
                        .disabled(busy || selected == nil)
                        .opacity(selected == nil ? 0.5 : 1)
                    Text("Cancel anytime. Secure checkout")
                        .font(Font2.sans(11, .medium)).foregroundStyle(Theme.ink.opacity(0.35))
                    HStack(spacing: 18) {
                        Button("Terms") { legal = .terms }
                        Button("Restore") { restore() }
                        Button("Privacy") { legal = .privacy }
                    }
                    .font(Font2.sans(11, .medium)).foregroundStyle(Theme.ink.opacity(0.4))
                })
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                CircleIconButton(icon: "xmark") { onClose() }
                    .padding(.top, 8).padding(.trailing, 18)
            }
        }
        .task {
            if premium.plans.isEmpty { await premium.loadPlans() }
        }
        // Never auto-skip: the paywall is a fixed onboarding step, whatever the premium status.
        // Already-subscribed users (reinstall / active sub) pass by tapping Restore, which flips
        // isPremium and unlocks here. A fresh purchase unlocks the same way.
        .onChange(of: premium.isPremium) { _, now in if now { unlock() } }
        .alert(notice?.title ?? "", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: {
            Text(notice?.message ?? "")
        }
        .sheet(item: $legal) { k in
            NavigationStack { LegalView(kind: k) }
                .presentationCornerRadius(34)
                .presentationDragIndicator(.visible)
        }
        .animation(Motion.snappy, value: premium.plans)
    }

    @ViewBuilder private var plansSection: some View {
        if premium.plans.isEmpty {
            VStack(spacing: 12) {
                if let err = premium.plansError {
                    Text(err)
                        .font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Haptics.tap()
                        Task { await premium.loadPlans() }
                    } label: {
                        Text("Try again").font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Theme.chipFill, in: Capsule())
                    }
                } else {
                    ProgressView().tint(Theme.mauve)
                    Text("Loading plans…").font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 26)
        } else {
            VStack(spacing: 10) {
                ForEach(premium.plans) { p in
                    Button { selectedID = p.id; Haptics.select() } label: { planRow(p) }
                        .buttonStyle(PressableStyle())
                }
            }
            .animation(Motion.snappy, value: selectedID)
        }
    }

    private func planRow(_ p: Premium.Plan) -> some View {
        let on = p.id == selected?.id
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(on ? Theme.rose : Theme.ring, lineWidth: 2).frame(width: 24, height: 24)
                if on { Circle().fill(Theme.rose).frame(width: 14, height: 14) }
            }
            Text(p.title).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
            if let badge = p.badge {
                Text(badge).font(Font2.sans(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.olive, in: Capsule())
            }
            Spacer()
            Text(p.price).font(Font2.sans(15, .heavy)).foregroundStyle(Theme.ink)
        }
        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? Theme.ink : Theme.ring, lineWidth: on ? 2 : 1))
    }

    // MARK: Actions

    private func buy() {
        guard let plan = selected, !busy else { return }
        busy = true; notice = nil
        Task {
            do {
                if try await premium.purchase(plan) { Haptics.success(); unlock() }
            } catch {
                notice = Notice(title: "Payment failed",
                                message: "The purchase didn't go through — you weren't charged. Please try again.")
            }
            busy = false
        }
    }

    private func restore() {
        guard !busy else { return }
        busy = true; notice = nil
        Task {
            let (restored, msg) = await premium.restoreOutcome()
            if restored { Haptics.success(); unlock() }
            else { notice = Notice(title: "Restore purchases",
                                   message: msg ?? "No active subscription found on this Apple ID.") }
            busy = false
        }
    }

    /// Purchase, restore, and the already-premium check can all race to finish — fire once.
    private func unlock() {
        guard !didUnlock else { return }
        didUnlock = true
        onUnlocked()
    }
}

/// Social proof: a row of overlapping member photos with a floating "Join N women" pill,
/// shown above the paywall headline. Photos fall back to soft gradients if the assets are absent.
private struct SocialProofCluster: View {
    private let photos = ["onb_g4", "onb_g8", "onb_g11", "onb_g14"]
    var count: String = "1,000+"

    var body: some View {
        VStack(spacing: -18) {                       // the pill floats over the photos' lower edge
            HStack(spacing: -20) {                   // overlapping avatars
                ForEach(Array(photos.enumerated()), id: \.offset) { _, name in
                    PhotoFill(name: name)
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                }
            }
            Text("Join \(count) women")
                .font(Font2.sans(15, .heavy)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

extension LegalView.Kind: Identifiable {
    var id: Self { self }
}
