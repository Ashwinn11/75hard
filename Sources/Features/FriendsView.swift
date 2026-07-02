import SwiftUI
import SwiftData
import UIKit

/// Friends tab — a real social layer over CloudKit. Share your invite code, add friends by
/// theirs, and once you've both accepted you can see each other's day and completion.
struct FriendsView: View {
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    private var challenge: Challenge? { challenges.first }

    @State private var social = SocialStore.shared
    @State private var showAdd = false
    @State private var selectedFriend: FriendStatus?

    private let accent = Theme.olive
    private var myName: String { challenge?.ownerName ?? "" }
    private var shareText: String {
        let who = myName.isEmpty ? "me" : myName
        if let c = social.myCode { return "Join \(who) on 75 Her — enter code \(SocialStore.format(c)) to start the challenge together." }
        return "Join me on 75 Her for the 75-day challenge."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header: "Your circle" title on the left, add-friends button on the right.
            HStack(alignment: .center) {
                SerifHeadline(lead: "Your", accent: "circle", size: 28, accentColor: accent, alignment: .leading)

                Spacer()

                if case .ready = social.phase {
                    CircleIconButton(icon: "person.badge.plus") { showAdd = true }
                        .overlay(alignment: .topTrailing) {
                            if !social.incoming.isEmpty {
                                Text("\(social.incoming.count)")
                                    .font(Font2.sans(11, .heavy)).foregroundStyle(.white)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .padding(.horizontal, social.incoming.count > 9 ? 4 : 0)
                                    .background(Theme.rose, in: Capsule())
                                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .accessibilityLabel(social.incoming.isEmpty ? "Add friends"
                            : "Add friends, \(social.incoming.count) requests")
                }
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 6)

            switch social.phase {
            case .unknown:
                loading
            case .unavailable(let message):
                unavailable(message)
            case .ready:
                friendsList
            }
        }
        .her75Background(accent)
        .task {
            await social.bootstrap()
            await social.setDisplayName(myName)
            if let c = challenge { await social.publishStatus(for: c) }
        }
        .sheet(isPresented: $showAdd) {
            AddFriendsSheet(accent: accent, myName: myName, shareText: shareText, challenge: challengeTitle)
                .presentationCornerRadius(34)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedFriend) { f in
            FriendProfileSheet(friend: f, accent: accent) {
                Task { await social.unfriend(f.id) }
            }
            .presentationCornerRadius(34)
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: States

    // Shimmering skeletons in the exact shape of friend cards while CloudKit connects.
    private var loading: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    SkeletonFriendCard().staggeredAppear(index: i)
                }
            }
            .padding(.horizontal, 20).padding(.top, 18)
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
        .accessibilityLabel("Connecting")
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 44, weight: .light)).foregroundStyle(accent)
                .symbolEffect(.pulse)
            Text(message)
                .font(Font2.serif(20, .medium)).italic()
                .foregroundStyle(Theme.ink.opacity(0.65)).multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                Task { await social.bootstrap() }
            } label: {
                Text("Try again").font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.chipFill, in: Capsule())
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var challengeTitle: String { challenge?.displayTitle ?? "75 Her" }

    private var friendsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if social.friends.isEmpty {
                    // No friends yet → the big invite ticket lives here so it's front-and-center.
                    MyInvitePanel(name: myName, code: social.myCode, shareText: shareText, accent: accent, challenge: challengeTitle)
                    AddFriendField(accent: accent,
                        lookup: { try await social.lookup($0) },
                        add: { try await social.accept($0) })
                    emptyFriends
                } else {
                    // Friends exist → just their daily checklists. Your code + adding lives behind +.
                    VStack(spacing: 16) {
                        ForEach(Array(social.friends.enumerated()), id: \.element.id) { i, f in
                            FriendRow(friend: f, accent: accent) { selectedFriend = f }
                                .staggeredAppear(index: i)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await social.refresh() }
        .animation(Motion.bouncy, value: social.friends)
    }

    private var emptyFriends: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2").font(.system(size: 30, weight: .light)).foregroundStyle(accent).symbolEffect(.pulse)
            Text("No friends yet. Share your code or add someone by theirs to check in on each other.")
                .font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26).softCard()
    }
}

private struct MyInvitePanel: View {
    let name: String
    let code: String?
    let shareText: String
    let accent: Color
    var challenge: String = "75 Her"
    var compact: Bool = false
    var body: some View {
        InviteTicket(name: name, code: code, compact: compact, shareText: shareText, challenge: challenge)
    }
}


// MARK: - Friend profile (avatar tap) — bio, their challenge, remove friend

private struct FriendProfileSheet: View {
    let friend: FriendStatus
    let accent: Color
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    private var ring: LinearGradient {
        LinearGradient(colors: [Theme.clay, Theme.mauve], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    InitialAvatar(name: friend.displayName, photo: friend.photo, seed: friend.id, size: 112)
                        .padding(4)
                        .overlay(Circle().stroke(ring, lineWidth: 3))
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text(friend.displayName).font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                        if !friend.bio.isEmpty {
                            Text(friend.bio)
                                .font(Font2.sans(15, .medium)).foregroundStyle(Theme.ink.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }

                    if !friend.challenge.isEmpty {
                        // The same challenge strip card used everywhere — their challenge's
                        // photos with the name on the floating pill. A custom-named challenge
                        // won't match a catalog title, so it falls back to the custom card.
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "On the challenge")
                            ChallengeStripCard(
                                track: ChallengeTrack.allCases.first { $0.title == friend.challenge } ?? .custom,
                                pillText: friend.challenge)
                            Text(friend.total > 0 ? "Day \(friend.day) · \(friend.done)/\(friend.total) done today"
                                                  : "Day \(friend.day)")
                                .font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Button(role: .destructive) { confirmRemove = true } label: {
                        Text("Remove friend")
                            .font(Font2.sans(15, .bold)).foregroundStyle(Theme.rose)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(.white, in: Capsule())
                            .overlay(Capsule().stroke(Theme.rose.opacity(0.4), lineWidth: 1.5))
                    }
                    .ctaWidth()
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Remove \(friend.displayName)?", isPresented: $confirmRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { Haptics.rigid(); onRemove(); dismiss() }
            } message: {
                Text("You'll stop seeing each other's progress. You can add them again anytime with their code.")
            }
        }
    }
}

// MARK: - Add friends sheet (code entry + friends-of-friends suggestions)

private struct AddFriendsSheet: View {
    let accent: Color
    let myName: String
    let shareText: String
    var challenge: String = "75 Her"

    @Environment(\.dismiss) private var dismiss
    @State private var social = SocialStore.shared
    @State private var loading = false

    // The list itself lives in the store, so a declined request or removed friend surfaces here
    // instantly. A person appears in exactly ONE place: friends → Friends tab, incoming/outgoing →
    // the Requests screen, everyone else → here. Tapping Add moves them out to Requests on the
    // spot; canceling there drops them straight back in.
    private var visibleSuggestions: [SuggestedPerson] {
        social.suggested.filter { s in
            !social.friends.contains { $0.id == s.id } &&
            !social.incoming.contains { $0.id == s.id } &&
            !social.outgoing.contains { $0.id == s.id }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !social.incoming.isEmpty || !social.outgoing.isEmpty {
                        NavigationLink { RequestsView(accent: accent) } label: {
                            RequestsNavRow(incoming: social.incoming.count, sent: social.outgoing.count)
                        }
                        .buttonStyle(PressableStyle())
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Your invite")
                        MyInvitePanel(name: myName, code: social.myCode, shareText: shareText, accent: accent, challenge: challenge, compact: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Add by code")
                        AddFriendField(accent: accent,
                            lookup: { try await social.lookup($0) },
                            add: { try await social.accept($0) })
                        Text("Ask a friend for their invite code.")
                            .font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Suggested")
                        if loading {
                            VStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { i in
                                    SkeletonPersonRow().staggeredAppear(index: i)
                                }
                            }
                            .allowsHitTesting(false)
                        } else if visibleSuggestions.isEmpty {
                            suggestionsEmpty
                        } else {
                            VStack(spacing: 12) {
                                ForEach(visibleSuggestions) { s in
                                    SuggestionRow(person: s, accent: accent) { send(s) }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Add friends").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .animation(Motion.snappy, value: social.outgoing)
            .animation(Motion.snappy, value: social.incoming)
            .animation(Motion.snappy, value: social.suggested)
        }
        .task {
            loading = social.suggested.isEmpty      // show cached list instantly, refresh behind it
            await social.loadSuggestions()
            loading = false
        }
    }

    private var suggestionsEmpty: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 26, weight: .light)).foregroundStyle(accent).symbolEffect(.pulse)
            Text("No one to suggest just yet — check back soon as more girls join.")
                .font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).softCard()
    }

    private func send(_ s: SuggestedPerson) {
        Haptics.success()
        Task { try? await social.accept(PersonRef(id: s.id, name: s.name, bio: s.bio, photo: s.photo)) }
    }
}

// MARK: - Requests (new + sent) — its own screen, pushed from the add sheet

private struct RequestsNavRow: View {
    let incoming: Int
    let sent: Int

    private var subtitle: String {
        var parts: [String] = []
        if incoming > 0 { parts.append("\(incoming) new") }
        if sent > 0 { parts.append("\(sent) sent") }
        return parts.isEmpty ? "All caught up" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "envelope")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44).background(Theme.chipFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Requests").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            if incoming > 0 {
                Text("\(incoming)")
                    .font(Font2.sans(12, .heavy)).foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, incoming > 9 ? 4 : 0)
                    .background(Theme.rose, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink.opacity(0.3))
        }
        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }
}

private struct RequestsView: View {
    let accent: Color
    @State private var social = SocialStore.shared
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if social.incoming.isEmpty && social.outgoing.isEmpty {
                    empty
                }
                if !social.incoming.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "New")
                        ForEach(social.incoming) { person in
                            RequestRow(person: person, accent: accent,
                                accept: { accept(person) },
                                ignore: { Task { await social.ignore(person.id) } })
                        }
                        if let message {
                            Text(message).font(Font2.sans(12, .medium)).foregroundStyle(Theme.rose)
                        }
                    }
                }
                if !social.outgoing.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Sent")
                        ForEach(social.outgoing) { person in
                            PendingRow(person: person, cancel: { Task { await social.remove(person.id) } })
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Requests").navigationBarTitleDisplayMode(.inline)
        .refreshable { await social.refresh() }
        .animation(Motion.snappy, value: social.incoming)
        .animation(Motion.snappy, value: social.outgoing)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 26, weight: .light)).foregroundStyle(accent).symbolEffect(.pulse)
            Text("No requests right now.").font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).softCard()
    }

    private func accept(_ person: PersonRef) {
        message = nil
        Task {
            do {
                try await social.accept(person)
                Ratings.note(.friendJoined)
            } catch { message = (error as? SocialError)?.errorDescription ?? "Couldn't accept right now. Try again." }
        }
    }
}

// Just photo · name · bio — the match scoring only drives the RANKING, it isn't shown.
// No "Sent" state: adding someone moves them out of this list and into Requests.
private struct SuggestionRow: View {
    let person: SuggestedPerson
    let accent: Color
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialAvatar(name: person.displayName, photo: person.photo, seed: person.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                if !person.bio.isEmpty {
                    Text(person.bio).font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Text("Add").font(Font2.sans(13, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(accent, in: Capsule())
            }
        }
        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }
}

// MARK: - Add friend by code

private struct AddFriendField: View {
    let accent: Color
    let lookup: (String) async throws -> PersonRef
    let add: (PersonRef) async throws -> Void

    @State private var draft = ""
    @State private var busy = false
    @State private var found: PersonRef?
    @State private var message: String?

    private var valid: Bool { SocialStore.sanitizeCode(draft).count >= 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("enter a friend's code", text: $draft)
                    .font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onChange(of: draft) { _, new in
                        draft = SocialStore.sanitizeCode(new)
                        found = nil; message = nil            // typing invalidates a prior lookup
                    }
                    .onSubmit(check)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Theme.ring, lineWidth: 1.5))

                Button(action: check) {
                    Image(systemName: busy ? "hourglass" : "magnifyingglass")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(accent, in: Circle())
                        .shadow(color: accent.opacity(0.3), radius: 8, y: 4)
                }
                .disabled(!valid || busy).opacity(valid && !busy ? 1 : 0.5)
            }

            if let message {
                Text(message).font(Font2.sans(12, .medium)).foregroundStyle(Theme.rose)
            }
            if let found {
                // Same card as a suggestion — avatar, name, bio — so a looked-up code
                // reads as a real profile before you send the request.
                SuggestionRow(person: SuggestedPerson(id: found.id, name: found.name, bio: found.bio, photo: found.photo),
                              accent: accent) { send(found) }
            }
        }
        .animation(Motion.snappy, value: found?.id)
    }

    private func check() {
        guard valid, !busy else { return }
        busy = true; message = nil; found = nil
        Task {
            do { found = try await lookup(draft) }
            catch { message = (error as? LocalizedError)?.errorDescription ?? "Couldn't find that code." }
            busy = false
        }
    }

    private func send(_ p: PersonRef) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await add(p)
                Haptics.success(); draft = ""; found = nil; message = nil
            } catch {
                message = (error as? SocialError)?.errorDescription ?? "Couldn't send the request. Try again."
            }
            busy = false
        }
    }
}

// MARK: - Rows

struct FriendRow: View {
    let friend: FriendStatus
    let accent: Color
    var onTapAvatar: () -> Void = {}
    /// Onboarding-only: how many habits are visually checked (nil = use h.done directly)
    var tickedCount: Int? = nil
    /// Onboarding-only: toggled per-habit to fire the pop bounce
    var bumpID: [Bool] = []

    private var ring: LinearGradient {
        LinearGradient(colors: [Theme.clay, Theme.mauve], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button { Haptics.tap(); onTapAvatar() } label: {
                VStack(spacing: 8) {
                    InitialAvatar(name: friend.displayName, photo: friend.photo, seed: friend.id, size: 68)
                        .padding(3)
                        .overlay(Circle().stroke(ring, lineWidth: 2.5))
                    VStack(spacing: 1) {
                        Text(friend.displayName).font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("Day \(friend.day)").font(Font2.sans(13, .medium)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .frame(width: 88)

            VStack(alignment: .leading, spacing: 12) {
                if friend.habits.isEmpty {
                    Text(friend.total > 0 ? "\(friend.done)/\(friend.total) done today" : "No check-ins yet")
                        .font(Font2.sans(14, .medium)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(friend.habits.prefix(3).enumerated()), id: \.element.id) { idx, h in
                        // In onboarding, done is driven by tickedCount; otherwise use h.done.
                        let isDone = tickedCount.map { idx < $0 } ?? h.done
                        let bump   = bumpID.indices.contains(idx) ? bumpID[idx] : false
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21, weight: .regular))
                                .foregroundStyle(isDone ? Theme.ink : Theme.ring)
                                // Pop bounce when this specific habit gets ticked.
                                .scaleEffect(isDone ? 1.0 : 1.0)   // stable baseline
                                .id(bump)   // identity change triggers the transition below
                                .transition(.scale(scale: 1.35).combined(with: .opacity))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.title)
                                    .font(Font2.sans(14, isDone ? .semibold : .medium))
                                    .foregroundStyle(isDone ? Theme.ink : Theme.ink.opacity(0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                                if isDone, !h.time.isEmpty {
                                    Text(h.time).font(Font2.sans(11, .medium)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .animation(Motion.bouncy, value: isDone)
                    }
                    if friend.habits.count > 3 {
                        Text("+\(friend.habits.count - 3) more")
                            .font(Font2.sans(12, .bold)).foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}


private struct RequestRow: View {
    let person: PersonRef
    let accent: Color
    let accept: () -> Void
    let ignore: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialAvatar(name: person.displayName, photo: person.photo, seed: person.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("wants to be friends").font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: { Haptics.success(); accept() }) {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(accent, in: Circle())
            }
            Button(action: { Haptics.light(); ignore() }) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40).background(Theme.chipFill, in: Circle())
            }
        }
        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }
}

private struct PendingRow: View {
    let person: PersonRef
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialAvatar(name: person.displayName, photo: person.photo, seed: person.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("request sent").font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: { Haptics.light(); cancel() }) {
                Text("Cancel").font(Font2.sans(13, .bold)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.chipFill, in: Capsule())
            }
        }
        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

// MARK: - Skeletons (loading placeholders, swept by the Metal shimmer)

private func skeletonBar(_ width: CGFloat, _ height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: height / 2).fill(Theme.chipFill)
        .frame(width: width, height: height)
}

/// Loading stand-in for FriendRow — same silhouette: avatar + name left, checklist right.
private struct SkeletonFriendCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                Circle().fill(Theme.chipFill).frame(width: 68, height: 68)
                skeletonBar(58, 12)
                skeletonBar(42, 9)
            }
            .frame(width: 88)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 11) {
                        Circle().fill(Theme.chipFill).frame(width: 21, height: 21)
                        skeletonBar([150, 110, 130][i], 11)
                    }
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .skeletonShimmer()
    }
}

/// Loading stand-in for SuggestionRow — avatar, two text lines, Add-button capsule.
private struct SkeletonPersonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Theme.chipFill).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 7) {
                skeletonBar(110, 12)
                skeletonBar(160, 9)
            }
            Spacer(minLength: 8)
            Capsule().fill(Theme.chipFill).frame(width: 58, height: 34)
        }
        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        .skeletonShimmer()
    }
}

// MARK: - Small pieces

struct InitialAvatar: View {
    let name: String
    var photo: Data? = nil
    var accent: Color = Theme.olive
    var seed: String? = nil          // stable identity (userID) → same color for a person everywhere
    var size: CGFloat = 48
    private var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    private var color: Color {
        guard let seed else { return accent }
        // Deterministic hash (String.hashValue is randomized per launch) → fixed palette pick.
        var h = 5381
        for b in seed.utf8 { h = (h &* 33) &+ Int(b) }
        let palette = [Theme.clay, Theme.mist, Theme.olive, Theme.mauve, Theme.sand]
        return palette[abs(h) % palette.count]
    }

    var body: some View {
        ZStack {
            if let photo, let ui = UIImage(data: photo) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [color.opacity(0.9), color], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initial).font(Font2.serif(size * 0.5, .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

