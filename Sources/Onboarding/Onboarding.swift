import SwiftUI
import SwiftData

// MARK: - Model
// (HabitDraft lives in Sources/Models/Models.swift — the widget target compiles the shared
// EditTaskSheet in UIComponents, so the draft type must be visible there too.)

@Observable
final class OnboardingModel {
    var name = ""
    var wantMost: String?
    var dailyVibe: String?
    var hardest: String?
    var track: ChallengeTrack = .her75
    var trackPicked = false
    var lengthDays = 75
    var startDate = Calendar.current.startOfDay(for: Date())
    var habitDrafts: [HabitDraft] = []
    var customName = ""                 // user-given name for a custom challenge

    /// What to show anywhere the picked challenge is named.
    var challengeTitle: String {
        track == .custom && !customName.isEmpty ? customName : track.title
    }

    func pick(_ t: ChallengeTrack) {
        track = t; trackPicked = true
        lengthDays = t.defaultDays
        habitDrafts = t.defaultHabits.map { HabitDraft(seed: $0) }
    }
}

// MARK: - Flow

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @State private var model = OnboardingModel()
    @State private var step = 0
    @State private var forward = true       // so Back slides the right way
    private let last = 17
    private let loadingStep = 14

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                stepView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if step >= 1 && step != loadingStep {   // loading has no back
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink).frame(width: 38, height: 38)
                        .background(Color.white, in: Circle()).overlay(Circle().stroke(Theme.ring, lineWidth: 1))
                }
            }
            if (5...11).contains(step) {        // quiz → length: setup progress
                ProgressBarThin(value: Double(step - 4) / 7.0, track: Theme.ring, fill: Theme.ink, height: 6)
                    .frame(maxWidth: 170)
                    .animation(Motion.gentle, value: step)
            }
            Spacer()
        }
        .padding(.horizontal, 20).frame(height: 52).padding(.top, 8)
        .opacity(step == 0 ? 0 : 1)
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case 0:  WelcomeStep(onNext: next)
        case 1:  AppPreviewStep(model: model, onNext: next)
        case 2:  FriendsPreviewStep(onNext: next)
        case 3:  ChipsStep(onNext: next)
        case 4:  NameStep(model: model, onNext: next)
        case 5:  QuizStep(lead: "What do you", accent: "want", trail: "most?",
                          options: ["Discipline", "Confidence", "More energy", "Peace of mind"],
                          photo: "onb_q_want", color: Theme.sand, selection: bind(\.wantMost), onNext: next)
        case 6:  QuizStep(lead: "What's your", accent: "daily", trail: "vibe?",
                          options: ["Calm & slow", "Busy & driven", "Social & fun", "Quiet & focused"],
                          photo: "onb_q_vibe", color: Theme.clay, selection: bind(\.dailyVibe), onNext: next)
        case 7:  QuizStep(lead: "What's the", accent: "hardest?", trail: nil,
                          options: ["Staying consistent", "Sugar cravings", "Enough sleep", "Screen time"],
                          photo: "onb_q_hard", color: Theme.mist, selection: bind(\.hardest), onNext: next)
        case 8:  ChooseChallengeStep(model: model, onNext: next)
        case 9:  ChallengeDetailStep(model: model, onNext: next)
        case 10: StartDateStep(model: model, onNext: next)
        case 11: LengthStep(model: model, onNext: next)
        case 12: PartnerUpStep(onPartner: next, onSolo: { skip(to: loadingStep) })
        case 13: InviteTicketStep(model: model, onNext: next)
        case 14: LoadingStep(onNext: next)
        case 15: ReadyStep(model: model, onNext: next)
        case 16: SignPromiseStep(onNext: next)
        default: PaywallView(days: model.lengthDays, onUnlocked: finish)
        }
    }

    private func bind(_ key: ReferenceWritableKeyPath<OnboardingModel, String?>) -> Binding<String?> {
        Binding(get: { model[keyPath: key] }, set: { model[keyPath: key] = $0 })
    }
    private func next() { forward = true; withAnimation(Motion.gentle) { step = min(step + 1, last) } }
    private func back() { forward = false; withAnimation(Motion.gentle) { step = max(step - 1, 0) } }
    private func skip(to s: Int) { forward = s >= step; withAnimation(Motion.gentle) { step = min(max(s, 0), last) } }

    private func finish() {
        if model.habitDrafts.isEmpty { model.pick(model.track) }
        let c = Challenge(track: model.track, lengthDays: model.lengthDays, startDate: model.startDate, ownerName: model.name)
        c.customTitle = model.customName
        context.insert(c)
        for (i, d) in model.habitDrafts.enumerated() {
            let h = Habit(title: d.title, subtitle: d.subtitle, color: d.color, icon: d.icon, photoName: d.photo, order: i)
            h.challenge = c
            context.insert(h)
        }
        try? context.save()
        // Persist quiz answers for friend-matching; SocialStore publishes them to the profile.
        AppGroup.defaults.set(model.wantMost ?? "", forKey: "onbWant")
        AppGroup.defaults.set(model.dailyVibe ?? "", forKey: "onbVibe")
        AppGroup.defaults.set(model.hardest ?? "", forKey: "onbHardest")
        Haptics.success()
    }
}

// CTA buttons are ~75% of the screen width (per the reference), centered.
// Internal: PaywallView (Sources/Premium) shares this bottom-CTA layout.
func ctaPad<V: View>(_ v: V) -> some View {
    HStack(spacing: 0) {
        Spacer(minLength: 0)
        v.containerRelativeFrame(.horizontal) { w, _ in w * 0.75 }
        Spacer(minLength: 0)
    }
    .padding(.bottom, 22)
}

/// The rounded bottom card that holds the headline + CTA on the early onboarding screens.
private struct OnbBottomCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 16) { content() }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
            .padding(.horizontal, 16).padding(.bottom, 18)
    }
}

// MARK: - 0 Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PhotoMarquee().frame(height: 360).clipped()
                FloatingPill {
                    Text("loved by thousands of women").font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                }
                .padding(.top, 6)
                .popIn(delay: 0.5)
            }
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Become her,", accent: "gently", size: 28, accentColor: Theme.rose, alignment: .center)
                PrimaryButton(title: "Let's do this", action: onNext)
            }
        }
    }
}

// MARK: - 1 App preview

private struct AppPreviewStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AppScreenshot().popIn(delay: 0.15, from: 0.88)
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Welcome to your next", accent: "75 days", size: 28, accentColor: Theme.clay, alignment: .center)
                PrimaryButton(title: "Continue", color: Theme.mist, action: onNext)
            }
        }
    }
}

// MARK: - 2 Friends preview

private struct FriendsPreviewStep: View {
    var onNext: () -> Void

    // All habits start unchecked — the animation ticks them in after the cards land.
    private let peeks: [FriendStatus] = [
        FriendStatus(id: "preview-mia", name: "Mia", day: 38, done: 0, total: 3,
                     challenge: "Her 75 Challenge", updatedAt: nil, photo: AppImage.data("onb_g5"),
                     habits: [FriendHabit(title: "One 45-minute workout", done: false, time: ""),
                              FriendHabit(title: "Drink only water",       done: false, time: ""),
                              FriendHabit(title: "Read 10 pages",           done: false, time: "")]),
        FriendStatus(id: "preview-priya", name: "Priya", day: 12, done: 0, total: 3,
                     challenge: "75 Soft", updatedAt: nil, photo: AppImage.data("onb_g11"),
                     habits: [FriendHabit(title: "Walk 10,000 steps", done: false, time: ""),
                              FriendHabit(title: "Eat clean",          done: false, time: ""),
                              FriendHabit(title: "Progress photo",     done: false, time: "")]),
    ]

    // tickedCount[cardIndex] = how many habits have been checked so far on that card.
    @State private var tickedCount: [Int] = [0, 0]
    // bumpID[cardIndex][habitIndex] — toggled each time that circle pops, driving .bouncy.
    @State private var bumpID: [[Bool]] = [[false, false, false], [false, false, false]]

    // Flattened tick schedule: (cardIndex, habitIndex, delay)
    private var tickSchedule: [(card: Int, habit: Int, delay: Double)] {
        // Cards stagger-appear over ~0.6 s. Start ticking at 0.9 s.
        let base = 0.9
        let gap  = 0.55
        return [
            (0, 0, base),
            (0, 1, base + gap),
            (1, 0, base + gap * 2),
            (0, 2, base + gap * 3),
            (1, 1, base + gap * 4),
            (1, 2, base + gap * 5),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                ForEach(Array(peeks.enumerated()), id: \.element.id) { i, f in
                    FriendRow(
                        friend: f,
                        accent: Theme.olive,
                        tickedCount: tickedCount[i],
                        bumpID: bumpID[i]
                    )
                    .rotationEffect(.degrees(i.isMultiple(of: 2) ? -2.2 : 2.2))
                    .offset(x: i.isMultiple(of: 2) ? -12 : 12)
                    .staggeredAppear(index: i)
                }
            }
            .padding(.horizontal, 30)
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Follow your", accent: "friends", size: 32, accentColor: Theme.olive, alignment: .center)
                PrimaryButton(title: "Continue", color: Theme.olive, action: onNext)
            }
        }
        .onAppear { scheduleTicks() }
    }

    private func scheduleTicks() {
        for t in tickSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + t.delay) {
                withAnimation(Motion.bouncy) {
                    if tickedCount[t.card] == t.habit {
                        tickedCount[t.card] += 1
                    }
                    bumpID[t.card][t.habit].toggle()
                }
                Haptics.light()
            }
        }
    }
}

// MARK: - 3 Chips

private struct ChipsStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    if AppImage.exists("onb_her") {
                        PhotoFill(name: "onb_her").frame(height: 380)
                    } else {
                        Theme.espressoGradient.frame(height: 380)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).padding(.horizontal, 30)
                AnimatedChips(items: [("heart.fill", "healthy"), ("bolt.fill", "fit"),
                                      ("sparkles", "glowing"), ("scope", "focused"), ("leaf.fill", "calm")])
                    .padding(.horizontal, 30)   // match the photo bounds so chips hug its corners
            }
            Spacer(minLength: 18)
            OnbBottomCard {
                VStack(spacing: 2) {
                    TypewriterHeadline(lead: "Become Her", size: 36, alignment: .center)
                    Text("(in 75 days)").font(Font2.serif(22, .medium)).italic().foregroundStyle(Theme.clay)
                }
                PrimaryButton(title: "I'm ready", color: Theme.olive, action: onNext)
            }
        }
    }
}

// MARK: - 4 Name

private struct NameStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @FocusState private var focused: Bool
    private var empty: Bool { model.name.trimmingCharacters(in: .whitespaces).isEmpty }
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "What's your", accent: "name?", size: 34, accentColor: Theme.rose, alignment: .center)
                .padding(.top, 10).padding(.horizontal, 24)
            TextField("First name", text: $model.name)
                .font(Font2.serif(28, .medium)).multilineTextAlignment(.center)
                .focused($focused).textInputAutocapitalization(.words).padding(.top, 28)
            // The signature line draws itself out as the keyboard arrives.
            Rectangle().fill(focused ? Theme.mauve.opacity(0.6) : Theme.ring)
                .frame(width: focused ? 220 : 70, height: 1.5).padding(.top, 6)
                .animation(Motion.gentle, value: focused)
            Spacer()
            if AppImage.exists("onb_name") {
                PhotoFill(name: "onb_name").frame(height: 220).frame(maxWidth: .infinity).clipped()
            }
            ctaPad(PrimaryButton(title: "Continue", color: Theme.mauve, action: { focused = false; onNext() })
                .disabled(empty).opacity(empty ? 0.5 : 1)).padding(.top, 12)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

// MARK: - 5–7 Quiz

private struct QuizStep: View {
    let lead: String; let accent: String; let trail: String?
    let options: [String]; let photo: String
    var color: Color = Theme.mauve
    @Binding var selection: String?
    var onNext: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterHeadline(lead: lead, accent: accent, trail: trail, size: 32, accentColor: Theme.ink, accentItalic: false)
                .padding(.horizontal, 24).padding(.top, 6)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(options.enumerated()), id: \.element) { i, opt in
                    OptionPill(text: opt, selected: selection == opt) { selection = opt }
                        .staggeredAppear(index: i)
                }
            }.padding(.horizontal, 24).padding(.top, 22)
            Spacer()
            if selection != nil, AppImage.exists(photo) {
                PhotoFill(name: photo).frame(height: 200).frame(maxWidth: .infinity).clipped().transition(.opacity)
            }
            ctaPad(PrimaryButton(title: "Continue", color: color, action: onNext)
                .disabled(selection == nil).opacity(selection == nil ? 0.5 : 1)).padding(.top, 12)
        }
        .animation(Motion.gentle, value: selection)
    }
}

// MARK: - 7 Choose challenge (scrollable library)

private struct ChooseChallengeStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "Choose your", accent: "challenge", size: 34, accentColor: Theme.ink, alignment: .center)
                .padding(.top, 6)
            HStack(spacing: 28) {                              // Popular / Custom tabs
                VStack(spacing: 6) {
                    Text("Popular").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                    Rectangle().fill(Theme.ink).frame(width: 64, height: 2.5)
                }
                Button { Haptics.select(); model.pick(.custom); onNext() } label: {   // Custom → custom detail
                    VStack(spacing: 6) {
                        Text("Custom").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink.opacity(0.35))
                        Rectangle().fill(.clear).frame(width: 64, height: 2.5)
                    }
                }.buttonStyle(.plain)
            }.padding(.top, 14)
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(Array(ChallengeTrack.catalog.enumerated()), id: \.element.id) { i, t in
                        Button { Haptics.select(); model.pick(t); onNext() } label: { ChallengeStripCard(track: t) }
                            .buttonStyle(PressableStyle())
                            .staggeredAppear(index: i)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 8 Challenge detail (numbered sticky task list, editable)
// Internal: the Profile challenge picker re-runs this + StartDateStep + LengthStep when switching.

struct ChallengeDetailStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var editing: Int?
    @FocusState private var nameFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    if model.track == .custom {
                        // Inline rename — the title IS the text field; the pencil just focuses it.
                        TextField("Custom Challenge", text: $model.customName)
                            .font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .focused($nameFocus).submitLabel(.done)
                            .fixedSize()
                        Button { Haptics.tap(); nameFocus = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.55))
                                .frame(width: 30, height: 30).background(Theme.chipFill, in: Circle())
                        }
                    } else {
                        Text(model.challengeTitle).font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                TaskListEditor(track: model.track,
                               items: model.habitDrafts.map { ($0.title, $0.color) },
                               onAdd: addTask, onEdit: { editing = $0 })
                ctaPad(PrimaryButton(title: "Continue", color: Theme.olive, action: onNext))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let i = editing, model.habitDrafts.indices.contains(i) {
                EditTaskSheet(draft: $model.habitDrafts[i], onSave: { Haptics.tap() },
                              onDelete: model.habitDrafts.count > 1 ? { model.habitDrafts.remove(at: i) } : nil)
            }
        }
    }

    private func addTask() {
        model.habitDrafts.append(HabitDraft(title: "New daily task", subtitle: "", color: .sage, icon: "plus"))
        editing = model.habitDrafts.count - 1
    }

}

// MARK: - 10 Start date

struct StartDateStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var mode = 0
    @Namespace private var pillNS
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "When do we", accent: "begin?", size: 32, accentColor: Theme.rose, alignment: .center).padding(.top, 6)
            Spacer()
            Text(bigWord).font(Font2.sans(64, .heavy)).foregroundStyle(Theme.ink).contentTransition(.numericText())
                .animation(Motion.snappy, value: mode)
            HStack(spacing: 10) {
                ForEach(Array(["Today", "Tomorrow", "Custom"].enumerated()), id: \.offset) { i, t in
                    SelectPill(text: t, selected: mode == i, hPad: 20, vPad: 12, slide: ("start", pillNS)) {
                        withAnimation(Motion.snappy) { mode = i }; apply(i)
                    }
                }
            }.padding(.top, 22)
            if mode == 2 {
                DatePicker("", selection: $model.startDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().tint(Theme.rose).padding(.top, 16)
            } else {
                Text(model.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(Font2.sans(13, .bold)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 12)
            }
            Spacer()
            ctaPad(PrimaryButton(title: "Continue", color: Theme.mauve, action: onNext))
        }
        .onAppear { apply(0) }
    }
    private var bigWord: String {
        switch mode { case 0: return "today"; case 1: return "tomorrow"
        default: return model.startDate.formatted(.dateTime.month(.abbreviated).day()) }
    }
    private func apply(_ i: Int) {
        let cal = Calendar.current
        if i == 0 { model.startDate = cal.startOfDay(for: Date()) }
        else if i == 1 { model.startDate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))! }
    }
}

// MARK: - 11 Length

struct LengthStep: View {
    @Bindable var model: OnboardingModel
    var ctaTitle = "Continue"
    var footnote: String? = nil            // e.g. the switch flow's "replaces your tasks" warning
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "How long is your", accent: "challenge?", size: 30, accentColor: Theme.rose, alignment: .center).padding(.top, 6)
            Spacer()
            LengthPicker(days: $model.lengthDays, startDate: model.startDate)
            Spacer()
            if let footnote {
                Text(footnote).font(Font2.sans(12, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.bottom, 10)
            }
            ctaPad(PrimaryButton(title: ctaTitle, color: Theme.sand, action: onNext))
        }
    }
}

// MARK: - 12 Partner up  →  13 Invite ticket

private struct PartnerUpStep: View {
    var onPartner: () -> Void        // "Partner Up" → opens the invite ticket
    var onSolo: () -> Void           // "I prefer solo" → skips ahead
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            Group {
                if AppImage.exists("onb_together") {
                    PhotoFill(name: "onb_together", anchor: UnitPoint(x: 0.5, y: 0.75))   // lower-middle: the two women, raised off the very bottom
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.olive.opacity(0.55), Theme.olive],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "person.2.fill").font(.system(size: 56, weight: .light)).foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 220).frame(maxWidth: .infinity).clipped()

            TypewriterHeadline(lead: "Do it", accent: "together", size: 34, accentColor: Theme.rose, alignment: .center).padding(.top, 8)
            Text("Add your friends, see their progress, and keep each other accountable through the challenge.")
                .font(Font2.sans(14, .medium)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 36).padding(.top, 8)
            FloatingPill {
                Text("together, you're twice as likely to finish")
                    .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
            }
            .padding(.top, 14)
                .popIn(delay: 0.4)
            Spacer()
            HStack(spacing: 10) {
                PrimaryButton(title: "Partner Up", icon: "person.badge.plus", color: Theme.clay, action: onPartner)
                Button { Haptics.tap(); onSolo() } label: {
                    Text("I prefer solo").font(Font2.sans(16, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 20).padding(.bottom, 22)
        }
    }
}

// MARK: - 13 Invite ticket (your join code)

private struct InviteTicketStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var social = SocialStore.shared

    private var shareText: String {
        let who = model.name.isEmpty ? "me" : model.name
        if let c = social.myCode { return "Join \(who) on 75 Her — enter code \(SocialStore.format(c)) to start the challenge together." }
        return "Join me on 75 Her for the 75-day challenge."
    }

    var body: some View {
        VStack(spacing: 0) {
            (Text("Start the challenge\n").font(Font2.serif(32, .semibold)).foregroundColor(Theme.ink)
             + Text("with").font(Font2.serif(32, .semibold)).italic().foregroundColor(Theme.ink)
             + Text(" your friends?").font(Font2.serif(32, .semibold)).foregroundColor(Theme.ink))
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
            FloatingPill {
                Text("together, you're twice as likely to finish")
                    .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
            }
            .padding(.top, 16)
                .popIn(delay: 0.4)
            Spacer()
            InviteTicket(name: model.name, code: social.myCode, challenge: model.challengeTitle)
                .padding(.horizontal, 22)
                .popIn(delay: 0.2, from: 0.92)
            Spacer()
            HStack(spacing: 12) {
                PrimaryButton(title: "Continue", color: Theme.mist, action: onNext)
                ShareLink(item: shareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .bold))
                        Text("Send invites").font(Font2.sans(17, .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.3), radius: 10, y: 5)
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            }
            .padding(.horizontal, 20).padding(.bottom, 22)
        }
        .task {
            await social.bootstrap()
            await social.setDisplayName(model.name)
        }
    }
}

// MARK: - 13 Loading

private struct LoadingStep: View {
    var onNext: () -> Void
    @State private var idx = 0
    @State private var rotate = false
    @State private var done = false
    private let lines = ["Saving your daily mission…", "Pinning your start date…", "Almost ready…"]
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.ring, lineWidth: 3)
                Circle().trim(from: 0, to: done ? 1 : 0.28)
                    .stroke(AngularGradient(colors: [Theme.clay, Theme.mauve, Theme.mist, Theme.clay],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(rotate ? 360 : 0))
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                    .scaleEffect(done ? 1 : 0.3).opacity(done ? 1 : 0)
            }
            .frame(width: 78, height: 78)
            Text(lines[min(idx, lines.count - 1)]).font(Font2.serif(20, .medium)).italic().foregroundStyle(Theme.ink.opacity(0.7))
                .contentTransition(.opacity)
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { rotate = true }
            for i in 1..<lines.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85 * Double(i)) {
                    withAnimation(Motion.gentle) { idx = i }
                    Haptics.light()
                }
            }
            // The ring completes, the check pops — a beat of "it's done" before moving on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(Motion.pop) { done = true }
                Haptics.success()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { onNext() }
        }
    }
}

// MARK: - 12 Ready / your plan (the sticker card, like 1505)

private struct ReadyStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var placed = false       // the plan card lands like a sticker being pressed on
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Congrats.").font(Font2.serif(34, .semibold)).foregroundStyle(Theme.ink)
                SerifHeadline(lead: "You're", accent: "ready", trail: "to start", size: 30, accentColor: Theme.rose)
            }
            .multilineTextAlignment(.center).padding(.top, 10).padding(.horizontal, 28)
            Spacer()
            planCard
                .scaleEffect(placed ? 1 : 1.16)
                .rotationEffect(.degrees(placed ? 0 : 3.5))
                .opacity(placed ? 1 : 0)
            Spacer()
            ctaPad(PrimaryButton(title: "Start now", color: Theme.mist, action: onNext))
        }
        .onAppear {
            withAnimation(Motion.bouncy.delay(0.3)) { placed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Haptics.rigid() }   // the "slap"
        }
    }

    private var planCard: some View {
        DayStickerCard(dayWords: "one",
                       range: challengeRangeText(start: model.startDate, days: model.lengthDays),
                       tasks: model.habitDrafts.map(\.title),
                       challengeTitle: model.challengeTitle)
            .padding(.horizontal, 34)
    }
}

// MARK: - 16 Sign your promise

private struct SignPromiseStep: View {
    var onNext: () -> Void
    @State private var strokes: [[CGPoint]] = []
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12, weight: .bold))
                    Text("9 in 10 who sign, finish").font(Font2.sans(12, .bold))
                }.foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.chipFill, in: Capsule())
                    .popIn(delay: 0.3)
                VStack(spacing: 2) {
                    TypewriterHeadline(lead: "Sign your", accent: "promise", size: 30, accentColor: Theme.rose, alignment: .center)
                    Text("A small commitment to yourself.").font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                }
                ZStack(alignment: .bottomTrailing) {
                    SignaturePad(strokes: $strokes).frame(height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ring, lineWidth: 1))
                    Button { strokes = [] } label: {
                        Text("Clear").font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink.opacity(0.5)).underline().padding(10)
                    }
                }
                // I commit / Skip live INSIDE the card — it wakes up the moment ink lands.
                PrimaryButton(title: "I commit", color: Theme.olive, action: onNext)
                    .disabled(strokes.isEmpty).opacity(strokes.isEmpty ? 0.5 : 1)
                    .scaleEffect(strokes.isEmpty ? 0.98 : 1)
                    .animation(Motion.bouncy, value: strokes.isEmpty)
                Button { onNext() } label: { Text("Skip").font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.5)).underline() }
            }
            .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10).padding(.horizontal, 20)
            Spacer()
        }
    }
}

// The paywall (final step) lives in Sources/Premium/PaywallView.swift — it's shared with
// RootGate, which re-shows it if the subscription ever lapses.
