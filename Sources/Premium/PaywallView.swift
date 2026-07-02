import SwiftUI

/// The real paywall — plans stream from RevenueCat's default offering. Premium-only app, so
/// there is no close button: this is the last onboarding step, and RootGate shows it full-screen
/// if the subscription ever lapses.
struct PaywallView: View {
    var days: Int = 75
    var onUnlocked: () -> Void

    @State private var premium = Premium.shared
    @State private var selectedID: String?
    @State private var busy = false
    @State private var message: String?
    @State private var restoreMessage: String?
    @State private var legal: LegalView.Kind?
    @State private var didUnlock = false

    private var selected: Premium.Plan? {
        premium.plans.first { $0.id == selectedID } ?? premium.plans.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text("Become Her in \(days) days")
                            .font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                        Text("Everything unlocked, every day")
                            .font(Font2.serif(26, .semibold)).foregroundStyle(Theme.ink)
                    }
                    .multilineTextAlignment(.center).padding(.top, 10)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(["Daily missions & proof photos",
                                 "Your honeycomb progress grid",
                                 "Friends & accountability"], id: \.self) { b in
                            Label(b, systemImage: "checkmark.circle.fill")
                                .font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
                        }
                    }
                    .padding(.top, 12)

                    plansSection.padding(.top, 16)

                    if let message {
                        Text(message)
                            .font(Font2.sans(12, .medium)).foregroundStyle(Theme.rose)
                            .multilineTextAlignment(.center).padding(.top, 6)
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)

            ctaPad(VStack(spacing: 10) {
                PrimaryButton(title: busy ? "One sec…" : "Become Her", color: Theme.mauve) { buy() }
                    .shimmerOnce(delay: 0.8)
                    .disabled(busy || selected == nil)
                    .opacity(selected == nil ? 0.5 : 1)
                Text("Auto-renews until canceled. Cancel anytime in the App Store.")
                    .font(Font2.sans(11, .medium)).foregroundStyle(Theme.ink.opacity(0.35))
                HStack(spacing: 18) {
                    Button("Terms") { legal = .terms }
                    Button("Restore") { restore() }
                    Button("Privacy") { legal = .privacy }
                }
                .font(Font2.sans(11, .medium)).foregroundStyle(Theme.ink.opacity(0.4))
            })
            .padding(.top, 8)
        }
        .task {
            if premium.isPremium { unlock() }               // already subscribed (reinstall) — skip the ask
            if premium.plans.isEmpty { await premium.loadPlans() }
        }
        .onChange(of: premium.isPremium) { _, now in if now { unlock() } }
        .alert("Restore purchases", isPresented: Binding(
            get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
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
        busy = true; message = nil
        Task {
            do {
                if try await premium.purchase(plan) { Haptics.success(); unlock() }
            } catch {
                message = "The purchase didn't go through — you weren't charged. Try again."
            }
            busy = false
        }
    }

    private func restore() {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            let (restored, msg) = await premium.restoreOutcome()
            if restored { Haptics.success(); unlock() } else { restoreMessage = msg }
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

extension LegalView.Kind: Identifiable {
    var id: Self { self }
}
