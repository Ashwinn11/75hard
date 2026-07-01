import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var showRestart = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var social = SocialStore.shared
    @State private var bioDraft = ""
    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            if let c = challenge {
                TabHeader(day: c.currentDay) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        nameEditor(c)
                        bioEditor
                        challengeSection(c)
                        restartButton
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                ContentUnavailableView("No challenge yet", systemImage: "person.crop.circle")
                Spacer()
            }
        }
        .her75Background()
        .task { await social.bootstrap() }
        .onAppear { bioDraft = social.myBio }
        .onChange(of: bioDraft) { _, v in if v.count > 140 { bioDraft = String(v.prefix(140)) } }
        .task(id: bioDraft) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, bioDraft != social.myBio else { return }
            await social.setBio(bioDraft)
        }
        .alert("Delete all data?", isPresented: $showRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) { restart() }
        } message: {
            Text("This erases your challenge, progress, photo, and profile — and removes you from CloudKit so no one can find you. You'll unfriend everyone and start completely fresh. This can't be undone.")
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    ProfilePhoto.save(data)
                    Haptics.success()
                    await social.syncPhoto()
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            if let c = challenge {
                ChallengePickerSheet(current: c.track) { switchChallenge(c, to: $0) }
            }
        }
    }

    // The selected challenge as a card; tap → all challenges (like onboarding).
    private func challengeSection(_ c: Challenge) -> some View {
        Button { showPicker = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowLabel(text: "Your challenge", color: Theme.ink.opacity(0.45))
                ChallengeStripCard(track: c.track)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func switchChallenge(_ c: Challenge, to t: ChallengeTrack) {
        c.trackRaw = t.rawValue
        c.lengthDays = t.defaultDays
        for h in c.habits { context.delete(h) }
        for (i, seed) in t.defaultHabits.enumerated() {
            let h = Habit(seed: seed, order: i)
            h.challenge = c
            context.insert(h)
        }
        try? context.save()
        Haptics.success()
    }

    private func headerCard(_ c: Challenge) -> some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileBubble(name: c.ownerName).scaleEffect(1.15)
                    Image(systemName: "camera.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(6).background(Theme.rose, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: c.track.title)
                Text(c.ownerName.isEmpty ? "That Girl" : c.ownerName)
                    .font(Font2.serif(28, .semibold)).foregroundStyle(Theme.ink)
                Text("Day \(c.currentDay) of \(c.lengthDays)")
                    .font(Font2.sans(13, .bold)).foregroundStyle(Theme.ink.opacity(0.55))
            }
            Spacer()
        }
    }

    private func nameEditor(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: "Your name", color: Theme.ink.opacity(0.45))
            TextField("Your name", text: Binding(
                get: { c.ownerName },
                set: { c.ownerName = $0; try? context.save() }))
                .font(Font2.sans(17, .bold)).foregroundStyle(Theme.ink)
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ring, lineWidth: 1))
        }
    }

    private var bioEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: "Your bio", color: Theme.ink.opacity(0.45))
            TextField("A short line about you — shown when friends find you.", text: $bioDraft, axis: .vertical)
                .font(Font2.sans(15, .medium)).foregroundStyle(Theme.ink)
                .lineLimit(2...4)
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ring, lineWidth: 1))
            Text("\(bioDraft.count)/140")
                .font(Font2.sans(11, .medium)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var restartButton: some View {
        Button(role: .destructive) { showRestart = true } label: {
            Text("Delete all data")
                .font(Font2.sans(15, .bold)).foregroundStyle(Theme.rose)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Theme.rose.opacity(0.4), lineWidth: 1.5))
        }
        .ctaWidth()
    }

    private func restart() {
        // Wipe CloudKit (profile, invite, my follow edges) + all local social/onboarding state.
        Task { await social.wipe() }
        // Delete the local challenge (+cascade habits/completions) → drops back to onboarding.
        if let c = challenge { context.delete(c); try? context.save() }
        Haptics.rigid()
    }
}

// MARK: - Challenge card (onboarding photo-strip style) + picker

struct ChallengeStripCard: View {
    let track: ChallengeTrack
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .top) {
                HStack(spacing: 3) {
                    ForEach(Array(track.photos.enumerated()), id: \.offset) { i, p in
                        PhotoFill(name: p, fallback: HabitColor.palette[(abs(track.rawValue.hashValue) + i) % HabitColor.palette.count].gradient)
                            .frame(maxWidth: .infinity).frame(height: 108).clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !track.joined.isEmpty {
                    Text(track.joined).font(Font2.sans(11, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2).offset(y: -11)
                }
            }
            Text(track.title).font(Font2.serif(22, .semibold)).foregroundStyle(Theme.ink)
        }
    }
}

struct ChallengePickerSheet: View {
    let current: ChallengeTrack
    var onSelect: (ChallengeTrack) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pending: ChallengeTrack?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(ChallengeTrack.catalog) { t in
                        Button { t == current ? dismiss() : (pending = t) } label: {
                            ChallengeStripCard(track: t)
                                .overlay(alignment: .topTrailing) {
                                    if t == current {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 24)).foregroundStyle(Theme.coral)
                                            .background(Circle().fill(.white)).padding(8)
                                    }
                                }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
            }
            .her75Background()
            .navigationTitle("Choose your challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Switch challenge?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Cancel", role: .cancel) { pending = nil }
                Button("Switch", role: .destructive) { if let t = pending { onSelect(t) }; dismiss() }
            } message: {
                Text("This replaces your current tasks with \(pending?.title ?? "the new challenge")'s and resets their progress. Your day count and start date stay.")
            }
        }
    }
}
