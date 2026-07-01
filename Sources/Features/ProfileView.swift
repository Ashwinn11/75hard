import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showBioEdit = false
    @State private var social = SocialStore.shared
    @AppStorage("profilePhotoV") private var photoVersion = 0
    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            if let c = challenge {
                TabHeader(day: c.currentDay, showAvatar: false) {
                    Button { Haptics.tap(); showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                }
                ScrollView {
                    VStack(spacing: 0) {
                        PhotosPicker(selection: $photoItem, matching: .images) { avatar }
                            .buttonStyle(PressableStyle())
                            .padding(.top, 26)
                        Text(c.ownerName.isEmpty ? "That Girl" : c.ownerName)
                            .font(Font2.serif(32, .semibold)).foregroundStyle(Theme.ink)
                            .padding(.top, 16)
                        bioLine
                            .padding(.top, 8)
                        challengeSection(c)
                            .padding(.top, 30)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
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
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showBioEdit) { NavigationStack { EditBioView() } }
    }

    // Big centered avatar — tap to change the photo.
    private var avatar: some View {
        ZStack {
            if let img = ProfilePhoto.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.roseGradient
                Image(systemName: "person.fill")
                    .font(.system(size: 52, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 128, height: 128).clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .id(photoVersion)
    }

    @ViewBuilder private var bioLine: some View {
        if social.myBio.isEmpty {
            Button { Haptics.tap(); showBioEdit = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .bold))
                    Text("Add a bio").font(Font2.sans(14, .bold))
                }
                .foregroundStyle(Theme.ink.opacity(0.55))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.chipFill, in: Capsule())
            }
        } else {
            Button { Haptics.tap(); showBioEdit = true } label: {
                Text(social.myBio)
                    .font(Font2.sans(15, .medium)).foregroundStyle(Theme.ink.opacity(0.65))
                    .multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.plain)
        }
    }

    // The selected challenge as a card; tap → all challenges (like onboarding).
    private func challengeSection(_ c: Challenge) -> some View {
        Button { showPicker = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowLabel(text: "Your challenge", color: Theme.ink.opacity(0.45))
                ChallengeStripCard(track: c.track, pillText: "Joined \(c.track.title)")
            }
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

// MARK: - Challenge card (onboarding photo-strip style) + picker

struct ChallengeStripCard: View {
    let track: ChallengeTrack
    var pillText: String? = nil      // override for the floating pill; nil → the track's joined count

    private var pill: String? { pillText ?? (track.joined.isEmpty ? nil : track.joined) }

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
                if let pill {
                    HStack(spacing: 5) {
                        if pillText != nil {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                        }
                        Text(pill).font(Font2.sans(11, .bold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2).offset(y: -11)
                }
            }
            if pillText == nil {   // pill already names the challenge — don't repeat it below
                Text(track.title).font(Font2.serif(22, .semibold)).foregroundStyle(Theme.ink)
            }
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
