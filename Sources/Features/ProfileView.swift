import SwiftUI
import SwiftData
import PhotosUI
import WidgetKit

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showBioEdit = false
    @State private var viewerDay: ProofDay?
    @State private var social = SocialStore.shared
    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            if let c = challenge {
                ScrollView {
                    VStack(spacing: 0) {
                        PhotosPicker(selection: $photoItem, matching: .images) { ProfileAvatar(size: 128) }
                            .buttonStyle(PressableStyle())
                            .padding(.top, 26)
                        Text(c.ownerName.isEmpty ? "Her" : c.ownerName)
                            .font(Font2.serif(32, .semibold)).foregroundStyle(Theme.ink)
                            .padding(.top, 16)
                        bioLine
                            .padding(.top, 8)
                        challengeSection(c)
                            .padding(.top, 30)
                        journeySection(c)
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .topTrailing) {
                    CircleIconButton(icon: "gearshape.fill") { showSettings = true }
                        .padding(.top, 12).padding(.trailing, 20)
                }
            } else {
                Spacer()
                ContentUnavailableView {
                    Label {
                        Text("No challenge yet")
                    } icon: {
                        Image(systemName: "person.crop.circle").symbolEffect(.pulse)
                    }
                }
                Spacer()
            }
        }
        .her75Background(Theme.mauve)
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
                ChallengePickerSheet(current: c.track) { t, drafts, start, days, customName in
                    switchChallenge(c, to: t, drafts: drafts, start: start, days: days, customName: customName)
                }
                .presentationCornerRadius(34)
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationCornerRadius(34)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBioEdit) {
            NavigationStack { EditBioView() }
                .presentationCornerRadius(34)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $viewerDay) { day in
            ProofViewer(shots: day.shots)
        }
    }

    // The proof-photo journey — a photo calendar of the challenge, inline. Tapping a day
    // with photos opens them full screen.
    private func journeySection(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Your journey")
            ProofCalendar(challenge: c) { dayShots in
                Haptics.tap()
                viewerDay = ProofDay(shots: dayShots)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                SectionTitle(text: "Your challenge")
                ChallengeStripCard(track: c.track, pillText: "Joined \(c.displayTitle)")
            }
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Apply a switch configured in the picker flow: new tasks (as edited), start date and length.
    /// The old habits go away with their history, so their proof-photo files go first.
    private func switchChallenge(_ c: Challenge, to t: ChallengeTrack, drafts: [HabitDraft], start: Date, days: Int, customName: String) {
        HabitActions.deleteProofPhotos(of: c)
        c.trackRaw = t.rawValue
        c.customTitle = customName
        c.lengthDays = days
        c.startDate = start
        for h in c.habits { context.delete(h) }
        for (i, d) in drafts.enumerated() {
            let h = Habit(title: d.title, subtitle: d.subtitle, color: d.color, icon: d.icon, photoName: d.photo, order: i)
            h.challenge = c
            context.insert(h)
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        Haptics.success()
        Task { await SocialStore.shared.publishStatus(for: c) }
    }
}

// MARK: - Challenge picker (switching re-runs the onboarding setup steps)

/// Picking a new challenge re-runs the real onboarding setup steps — task preview (editable),
/// start date, length — on a scratch OnboardingModel. Only the final "Start this challenge"
/// applies the switch.
struct ChallengePickerSheet: View {
    let current: ChallengeTrack
    var onSwitch: (ChallengeTrack, [HabitDraft], Date, Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var setup = OnboardingModel()

    private enum Step: Hashable { case tasks, start, length }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(Array(ChallengeTrack.catalog.enumerated()), id: \.element.id) { i, t in
                        Button {
                            if t == current { dismiss() }
                            else { Haptics.tap(); setup.pick(t); path.append(.tasks) }
                        } label: {
                            ChallengeStripCard(track: t)
                                .overlay(alignment: .topTrailing) {
                                    if t == current {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 24)).foregroundStyle(Theme.clay)
                                            .background(Circle().fill(.white)).padding(8)
                                    }
                                }
                        }
                        .buttonStyle(PressableStyle())
                        .staggeredAppear(index: i)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
            }
            .her75Background()
            .navigationTitle("Choose your challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(for: Step.self) { step in
                Group {
                    switch step {
                    case .tasks:
                        ChallengeDetailStep(model: setup) { path.append(.start) }
                    case .start:
                        StartDateStep(model: setup) { path.append(.length) }
                    case .length:
                        LengthStep(model: setup,
                                   ctaTitle: "Start this challenge",
                                   footnote: "This replaces your current tasks — progress starts fresh.") {
                            onSwitch(setup.track, setup.habitDrafts, setup.startDate, setup.lengthDays, setup.customName)
                            dismiss()
                        }
                    }
                }
                .her75Background()
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
