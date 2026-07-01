import SwiftUI
import SwiftData

// MARK: - Settings (gear on Profile) — name, bio, challenge duration, legal, subscription, wipe

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var social = SocialStore.shared
    @State private var confirmWipe = false
    private var challenge: Challenge? { challenges.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Profile") {
                        NavigationLink { EditNameView() } label: {
                            SettingsRow(title: "Your name", value: challenge?.ownerName ?? "")
                        }
                        rowDivider
                        NavigationLink { EditBioView() } label: {
                            SettingsRow(title: "Bio", value: social.myBio.isEmpty ? "Add" : social.myBio)
                        }
                    }

                    section("Challenge") {
                        NavigationLink { DurationView() } label: {
                            SettingsRow(title: "Duration", value: "\(challenge?.lengthDays ?? 75) days")
                        }
                    }

                    section("Legal") {
                        NavigationLink { LegalView(kind: .privacy) } label: {
                            SettingsRow(title: "Privacy Policy")
                        }
                        rowDivider
                        NavigationLink { LegalView(kind: .terms) } label: {
                            SettingsRow(title: "Terms of Service")
                        }
                    }

                    section("Subscription") {
                        Button {
                            Haptics.tap()
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                        } label: {
                            SettingsRow(title: "Manage subscription", chevron: "arrow.up.right")
                        }
                    }

                    section("Account") {
                        Button(role: .destructive) { confirmWipe = true } label: {
                            SettingsRow(title: "Delete all data", destructive: true, chevron: "trash")
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Delete all data?", isPresented: $confirmWipe) {
                Button("Cancel", role: .cancel) {}
                Button("Delete everything", role: .destructive) { wipeAll() }
            } message: {
                Text("This erases your challenge, progress, photo, and profile — and removes you from CloudKit so no one can find you. You'll unfriend everyone and start completely fresh. This can't be undone.")
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Font2.sans(12, .bold)).tracking(1.5).foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }

    private var rowDivider: some View { Divider().padding(.leading, 18) }

    private func wipeAll() {
        Haptics.rigid()
        Task { await social.wipe() }
        if let c = challenge { context.delete(c); try? context.save() }
        dismiss()
    }
}

// A settings list row: title · truncated value · chevron/icon.
private struct SettingsRow: View {
    let title: String
    var value: String = ""
    var destructive = false
    var chevron: String = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Font2.sans(16, .semibold))
                .foregroundStyle(destructive ? Theme.rose : Theme.ink)
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(value)
                    .font(Font2.sans(15, .medium)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .trailing)
            }
            Image(systemName: chevron)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(destructive ? Theme.rose : Theme.ink.opacity(0.3))
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Edit name

struct EditNameView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var draft = ""
    @State private var social = SocialStore.shared
    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "Your name", color: Theme.ink.opacity(0.45))
            TextField("Your name", text: $draft)
                .font(Font2.sans(17, .bold)).foregroundStyle(Theme.ink)
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ring, lineWidth: 1))
            Text("Shown to friends on your invite and your check-ins.")
                .font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            PrimaryButton.ink("Save") { save() }.ctaWidth()
        }
        .padding(20)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Your name").navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = challenge?.ownerName ?? "" }
    }

    private func save() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = challenge, !name.isEmpty else { dismiss(); return }
        c.ownerName = name
        try? context.save()
        Task { await social.setDisplayName(name) }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Edit bio

struct EditBioView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var social = SocialStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "Your bio", color: Theme.ink.opacity(0.45))
            TextField("A short line about you — shown when friends find you.", text: $draft, axis: .vertical)
                .font(Font2.sans(15, .medium)).foregroundStyle(Theme.ink)
                .lineLimit(3...6)
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ring, lineWidth: 1))
                .onChange(of: draft) { _, v in if v.count > 100 { draft = String(v.prefix(100)) } }
            Text("\(draft.count)/100")
                .font(Font2.sans(11, .medium)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Spacer()
            PrimaryButton.ink("Save") { save() }.ctaWidth()
        }
        .padding(20)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Your bio").navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = social.myBio }
    }

    private func save() {
        let bio = draft
        Task { await social.setBio(bio) }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Challenge duration (mimics the onboarding length step)

struct DurationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var days = 75
    private var challenge: Challenge? { challenges.first }
    private let presets = [7, 14, 30, 75]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RulerSlider(value: $days, range: 1...75, unit: "days", accent: Theme.sage)
                .padding(.horizontal, 16)
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { p in
                    Button { withAnimation { days = p }; Haptics.select() } label: {
                        Text("\(p)").font(Font2.sans(15, .bold)).foregroundStyle(days == p ? .white : Theme.ink)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(days == p ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.white), in: Capsule())
                            .overlay(Capsule().stroke(Theme.ring, lineWidth: days == p ? 0 : 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)
            Text(rangeText).font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 16)
            if let c = challenge, days < c.currentDay {
                Text("You're already on day \(c.currentDay) — the challenge can't be shorter than that.")
                    .font(Font2.sans(12, .medium)).foregroundStyle(Theme.rose)
                    .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.top, 10)
            }
            Spacer()
            PrimaryButton.ink("Save") { save() }.ctaWidth().padding(.bottom, 22)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Challenge length").navigationBarTitleDisplayMode(.inline)
        .onAppear { days = challenge?.lengthDays ?? 75 }
    }

    private var rangeText: String {
        guard let c = challenge else { return "" }
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: c.startDate) ?? c.startDate
        return "\(c.startDate.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func save() {
        guard let c = challenge else { dismiss(); return }
        c.lengthDays = max(days, c.currentDay)   // never shorter than the days already lived
        try? context.save()
        Task { await SocialStore.shared.publishStatus(for: c) }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Legal (terms / privacy)

struct LegalView: View {
    enum Kind { case terms, privacy }
    let kind: Kind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.0).font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink)
                        Text(s.1).font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Last updated July 2026")
                    .font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(kind == .terms ? "Terms of Service" : "Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [(String, String)] {
        switch kind {
        case .privacy:
            return [
                ("Your data lives on your device",
                 "Your challenge, daily check-ins, and proof photos are stored locally on your iPhone. We don't run our own servers and we never sell or share your data."),
                ("What friends can see",
                 "If you use the Friends feature, your display name, bio, profile photo, challenge name, and daily completion status are stored in Apple's iCloud (CloudKit) so the friends you connect with can see them. Anyone with the app can discover your name, bio, and photo through friend suggestions or your invite code."),
                ("Your invite code",
                 "Your code identifies you for friend requests only. It contains no personal information."),
                ("Photos",
                 "Proof photos you attach to check-ins never leave your device. Only your small profile picture is shared through iCloud."),
                ("No tracking",
                 "We don't use advertising, analytics trackers, or third-party data brokers."),
                ("Deleting your data",
                 "Settings → Delete all data erases everything on your device and removes your profile, invite code, and connections from iCloud. This is immediate and irreversible."),
            ]
        case .terms:
            return [
                ("What this app is",
                 "75 Her is a personal wellness companion for building daily habits. It is not medical, dietary, or mental-health advice. Consult a professional before starting any demanding fitness or diet program."),
                ("Your responsibility",
                 "You choose your challenge and its intensity. Listen to your body — rest when you need to. You are responsible for the name, bio, and photo you share with others."),
                ("Friends & conduct",
                 "The Friends feature connects you with people you choose. Keep names, bios, and photos respectful; we may remove content that's abusive or unlawful from CloudKit."),
                ("Subscription",
                 "Some features may require a subscription billed through your Apple ID. Manage or cancel anytime in your App Store account settings. Payment terms are shown before purchase."),
                ("No guarantees",
                 "The app is provided as-is. We work hard to keep your streaks safe, but we can't guarantee uninterrupted service and aren't liable for lost data caused by your device or iCloud."),
                ("Changes",
                 "We may update these terms as the app evolves; continued use means you accept the current version."),
            ]
        }
    }
}
