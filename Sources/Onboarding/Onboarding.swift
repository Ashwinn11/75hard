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

    /// The catalog track that best matches the quiz answers — pinned first on the
    /// choose-challenge step. A specific pain beats a general want beats the vibe.
    var recommendedTrack: ChallengeTrack {
        switch hardest {
        case "Sugar cravings": return .sugarFree
        case "Screen time":    return .mentalWellness
        case "Enough sleep":   return .glowUp
        default: break
        }
        switch wantMost {
        case "Peace of mind": return .mentalWellness
        case "More energy":   return .betterMe
        default: break
        }
        return dailyVibe == "Calm & slow" ? .soft : .her75
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
            // Loading + paywall own their nav. Ready (15) sits past the loader, so back
            // from it could only replay the loader — hidden there too.
            if step >= 1 && ![loadingStep, 15, last].contains(step) {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink).frame(width: 38, height: 38)
                        .background(Color.white, in: Circle()).overlay(Circle().stroke(Theme.ring, lineWidth: 1))
                }
            }
            if (3...10).contains(step) {        // quiz → length: setup progress
                ProgressBarThin(value: Double(step - 2) / 8.0, track: Theme.ring, fill: Theme.ink, height: 6)
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
        case 1:  FutureYouStep(onNext: next)
        case 2:  NameStep(model: model, onNext: next)
        case 3:  QuizStep(lead: "What do you", accent: "want", trail: "most?",
                          options: ["Discipline", "Confidence", "More energy", "Peace of mind"],
                          photo: "onb_q_want",
                          icons: ["flame.fill", "crown.fill", "bolt.fill", "leaf.fill"],
                          greeting: hello, selection: bind(\.wantMost), onNext: next)
        case 4:  QuizStep(lead: "What's your", accent: "daily", trail: "vibe?",
                          options: ["Calm & slow", "Busy & driven", "Social & fun", "Quiet & focused"],
                          photo: "onb_q_vibe",
                          icons: ["cloud.fill", "hare.fill", "party.popper.fill", "moon.stars.fill"],
                          selection: bind(\.dailyVibe), onNext: next)
        case 5:  QuizStep(lead: "What's the", accent: "hardest?", trail: nil,
                          options: ["Staying consistent", "Sugar cravings", "Enough sleep", "Screen time"],
                          photo: "onb_q_hard",
                          icons: ["arrow.clockwise", "birthday.cake.fill", "bed.double.fill", "iphone"],
                          selection: bind(\.hardest), onNext: next)
        case 6:  AppPreviewStep(onNext: next)
        case 7:  ChooseChallengeStep(model: model, onNext: next)
        case 8:  ChallengeDetailStep(model: model, onNext: next)
        case 9:  StartDateStep(model: model, onNext: next)
        case 10: LengthStep(model: model, onNext: next)
        case 11: FriendsPreviewStep(onNext: next)
        case 12: PartnerUpStep(onPartner: next, onSolo: { skip(to: loadingStep) })
        case 13: InviteTicketStep(model: model, onNext: next)
        case 14: LoadingStep(model: model, onNext: next)
        case 15: ReadyStep(model: model, onNext: next)
        case 16: SignPromiseStep(model: model, onNext: next)
        default: PaywallView(days: model.lengthDays, onUnlocked: finish,
                             onClose: { skip(to: 15) })   // Close → the plan preview (ReadyStep)
        }
    }

    /// The warm eyebrow on the first quiz step, once we know their name.
    private var hello: String? {
        let n = model.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : "nice to meet you, \(n)"
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

// CTA buttons span the full width with comfortable margins, anchored at the bottom.
// Internal: PaywallView (Sources/Premium) shares this bottom-CTA layout.
func ctaPad<V: View>(_ v: V) -> some View {
    v.padding(.horizontal, 20).padding(.bottom, 22)
}

// MARK: - 0 Welcome (typographic hero — the 75 days themselves are the visual)

private struct WelcomeStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // The app mark, treated exactly like the splash icon so launch → welcome feels continuous.
            Image("LaunchLogo")
                .resizable().scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
                .popIn(delay: 0.05, from: 0.8)
                .padding(.bottom, 16)
            Text("75 HER").font(Font2.sans(13, .heavy)).tracking(7).foregroundStyle(Theme.ink.opacity(0.4))
            DotCalendar().padding(.top, 26).padding(.horizontal, 28)
            Spacer()
            VStack(spacing: 12) {
                TypewriterHeadline(lead: "Show up for", accent: "yourself", size: 34, alignment: .center)
                Text("One challenge. 75 days. A new rhythm.")
                    .font(Font2.sans(14, .medium)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 28)
            ctaPad(PrimaryButton(title: "Start my 75", action: onNext)).padding(.top, 26)
        }
    }
}

// MARK: - 6 App preview (the breather bridging the quiz into setup)

private struct AppPreviewStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AppScreenshot().popIn(delay: 0.15, from: 0.88)
            Spacer()
            TypewriterHeadline(lead: "Your new daily", accent: "home", size: 30, alignment: .center)
                .padding(.horizontal, 28)
            ctaPad(PrimaryButton(title: "Set mine up", action: onNext)).padding(.top, 20)
        }
    }
}

// MARK: - 11 Friends preview (the social demo right before the partner ask)

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
                        accent: Theme.berry,
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
            TypewriterHeadline(lead: "Follow your", accent: "friends", size: 32, alignment: .center)
                .padding(.horizontal, 28)
            ctaPad(PrimaryButton(title: "Continue", action: onNext)).padding(.top, 20)
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

// MARK: - 1 Future you (trait tiles UNDER the photo — nothing overlaps the image)

private struct FutureYouStep: View {
    var onNext: () -> Void

    /// The transformation, not a feature list — milestones on the way to day 75,
    /// rising through a typographic crescendo and landing on the brand word.
    private let milestones: [(day: String, word: String)] = [
        ("DAY 10", "stronger"),
        ("DAY 30", "clearer"),
        ("DAY 50", "radiant"),
        ("DAY 75", "her."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if AppImage.exists("onb_her") {
                    PhotoFill(name: "onb_her").frame(height: 280)
                } else {
                    Theme.espressoGradient.frame(height: 280)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).padding(.horizontal, 24)

            // The journey ledger — quiet day markers, each line a little larger than the last.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(milestones.enumerated()), id: \.offset) { i, m in
                    let final = i == milestones.count - 1
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(m.day)
                            .font(Font2.sans(11, .heavy)).tracking(1.5)
                            .foregroundStyle(final ? Theme.berry : Theme.ink.opacity(0.35))
                            .frame(width: 56, alignment: .leading)
                        Text(m.word)
                            .font(Font2.serif(18 + CGFloat(i) * 1.7, final ? .semibold : .medium)).italic()
                            .foregroundStyle(final ? Theme.berry : Theme.ink.opacity(0.8))
                    }
                    .staggeredAppear(index: i)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40).padding(.top, 18)

            Spacer(minLength: 18)
            VStack(spacing: 6) {
                TypewriterHeadline(lead: "Meet the", accent: "future you", size: 32, alignment: .center)
                Text("built one day at a time")
                    .font(Font2.serif(20, .medium)).italic().foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 28)
            ctaPad(PrimaryButton(title: "I'm ready", action: onNext)).padding(.top, 18)
        }
    }
}

// MARK: - 2 Name

private struct NameStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @FocusState private var focused: Bool
    private var empty: Bool { model.name.trimmingCharacters(in: .whitespaces).isEmpty }
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "What's your", accent: "name?", size: 34, alignment: .center)
                .padding(.top, 10).padding(.horizontal, 24)
            TextField("First name", text: $model.name)
                .font(Font2.serif(28, .medium)).multilineTextAlignment(.center)
                .focused($focused).textInputAutocapitalization(.words).padding(.top, 28)
                .submitLabel(.continue)
                .onSubmit { if !empty { focused = false; onNext() } }
            // The signature line draws itself out as the keyboard arrives.
            Rectangle().fill(focused ? Theme.berry.opacity(0.6) : Theme.ring)
                .frame(width: focused ? 220 : 70, height: 1.5).padding(.top, 6)
                .animation(Motion.gentle, value: focused)
            Spacer()
            if AppImage.exists("onb_name") {
                PhotoFill(name: "onb_name").frame(height: 220).frame(maxWidth: .infinity).clipped()
            }
            ctaPad(PrimaryButton(title: "Continue", action: { focused = false; onNext() })
                .disabled(empty).opacity(empty ? 0.5 : 1)).padding(.top, 12)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

// MARK: - 3–5 Quiz (full-width option cards, radio-check selection)

private struct QuizStep: View {
    let lead: String; let accent: String; let trail: String?
    let options: [String]; let photo: String
    var icons: [String] = []             // leading chips, zipped with options
    var greeting: String? = nil          // one-time warm eyebrow ("nice to meet you, …")
    @Binding var selection: String?
    var onNext: () -> Void
    @Namespace private var selNS         // the gradient border travels between answers
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let greeting {
                Text(greeting)
                    .font(Font2.serif(16, .medium)).italic().foregroundStyle(Theme.berry)
                    .padding(.horizontal, 24).padding(.top, 6)
            }
            TypewriterHeadline(lead: lead, accent: accent, trail: trail, size: 32, accentColor: Theme.ink, accentItalic: false)
                .padding(.horizontal, 24).padding(.top, 6)
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.element) { i, opt in
                    OptionRow(title: opt,
                              icon: i < icons.count ? icons[i] : nil,
                              selectionNS: selNS,
                              selected: selection == opt) { selection = opt }
                        .staggeredAppear(index: i)
                }
            }.padding(.horizontal, 20).padding(.top, 22)
            Spacer()
            if selection != nil, AppImage.exists(photo) {
                PhotoFill(name: photo).frame(height: 200).frame(maxWidth: .infinity).clipped()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ctaPad(PrimaryButton(title: "Continue", action: onNext)
                .disabled(selection == nil).opacity(selection == nil ? 0.5 : 1)).padding(.top, 12)
        }
        .animation(Motion.gentle, value: selection)
    }
}

// MARK: - 7 Choose challenge (recommended-first library, quiz-personalized)

private struct ChooseChallengeStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void

    private var picked: ChallengeTrack { model.recommendedTrack }
    private var rest: [ChallengeTrack] { ChallengeTrack.catalog.filter { $0 != picked } }

    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "Choose your", accent: "challenge", size: 34, accentColor: Theme.ink, alignment: .center)
                .padding(.top, 6)
            Text("shaped by your answers")
                .font(Font2.serif(16, .medium)).italic().foregroundStyle(Theme.ink.opacity(0.5))
                .padding(.top, 4)
            ScrollView {
                VStack(spacing: 24) {
                    Button { Haptics.select(); model.pick(picked); onNext() } label: {
                        ChallengeStripCard(track: picked, pillText: "picked for you", pillIcon: "sparkles")
                    }
                    .buttonStyle(PressableStyle())
                    .staggeredAppear(index: 0)

                    HStack(spacing: 12) {
                        Rectangle().fill(Theme.ring).frame(height: 1)
                        Text("MORE CHALLENGES").font(Font2.sans(10, .heavy)).tracking(2)
                            .foregroundStyle(Theme.ink.opacity(0.35)).fixedSize()
                        Rectangle().fill(Theme.ring).frame(height: 1)
                    }
                    .staggeredAppear(index: 1)

                    ForEach(Array(rest.enumerated()), id: \.element.id) { i, t in
                        Button { Haptics.select(); model.pick(t); onNext() } label: { ChallengeStripCard(track: t) }
                            .buttonStyle(PressableStyle())
                            .staggeredAppear(index: i + 2)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
            }
            // Pinned under the list — the custom path (replaces the old Popular/Custom tabs).
            Button { Haptics.select(); model.pick(.custom); onNext() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                    Text("Build your own").font(Font2.sans(15, .bold))
                }
                .foregroundStyle(Theme.ink.opacity(0.65))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.28), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5])))
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
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
                ctaPad(PrimaryButton(title: "Continue", action: onNext))
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

// MARK: - 9 Start date (a strip of day cards — tap any of the next two weeks)

struct StartDateStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var showPicker = false

    private var strip: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "Pick your", accent: "day one", size: 32, alignment: .center).padding(.top, 6)
            Spacer()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(strip, id: \.self) { d in
                            DayCard(date: d,
                                    selected: Calendar.current.isDate(d, inSameDayAs: model.startDate)) {
                                withAnimation(Motion.snappy) { showPicker = false; model.startDate = d }
                                withAnimation(Motion.gentle) { proxy.scrollTo(d, anchor: .center) }
                            }
                            .id(d)
                            .scrollTransition(.interactive) { view, phase in
                                view.scaleEffect(phase.isIdentity ? 1 : 0.9)
                                    .opacity(phase.isIdentity ? 1 : 0.7)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 14)     // headroom for the selected card's lift + glow
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .onAppear {
                    if let sel = strip.first(where: { Calendar.current.isDate($0, inSameDayAs: model.startDate) }) {
                        proxy.scrollTo(sel, anchor: .center)
                    }
                }
            }
            Text("Starting \(model.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                .font(Font2.sans(13, .bold)).foregroundStyle(Theme.ink.opacity(0.5))
                .contentTransition(.numericText())
                .animation(Motion.snappy, value: model.startDate)
                .padding(.top, 16)
            Button {
                Haptics.tap()
                withAnimation(Motion.gentle) { showPicker.toggle() }
            } label: {
                Text(showPicker ? "Back to quick picks" : "Need a later date?")
                    .font(Font2.sans(13, .bold)).foregroundStyle(Theme.berry).underline()
            }
            .padding(.top, 10)
            if showPicker {
                DatePicker("", selection: $model.startDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().tint(Theme.berry).padding(.top, 12)
                    .transition(.opacity)
            }
            Spacer()
            ctaPad(PrimaryButton(title: "Continue", action: onNext))
        }
    }
}

/// One tappable day in the start-date strip: weekday, big day number, month.
private struct DayCard: View {
    let date: Date
    let selected: Bool
    var action: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Button { Haptics.select(); action() } label: {
            VStack(spacing: 5) {
                Text(isToday ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(Font2.sans(10, .heavy)).tracking(1)
                    .foregroundStyle(selected ? .white.opacity(0.75) : Theme.ink.opacity(0.45))
                Text(date.formatted(.dateTime.day()))
                    .font(Font2.sans(26, .heavy))
                    .foregroundStyle(selected ? .white : Theme.ink)
                Text(date.formatted(.dateTime.month(.abbreviated)).lowercased())
                    .font(Font2.sans(11, .medium))
                    .foregroundStyle(selected ? .white.opacity(0.75) : Theme.ink.opacity(0.45))
            }
            .frame(width: 64).padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.55)))
                    .opacity(selected ? 0 : 1)
                if selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.berryGradient)
                }
            }
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1)
                }
            }
            .shadow(color: selected ? Theme.berry.opacity(0.32) : .black.opacity(0.05),
                    radius: selected ? 14 : 10, y: selected ? 7 : 4)
            .scaleEffect(selected ? 1.06 : 1)
            .offset(y: selected ? -4 : 0)
            .animation(Motion.bouncy, value: selected)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - 10 Length

struct LengthStep: View {
    @Bindable var model: OnboardingModel
    var ctaTitle = "Continue"
    var footnote: String? = nil            // e.g. the switch flow's "replaces your tasks" warning
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "How long is your", accent: "challenge?", size: 30, alignment: .center).padding(.top, 6)
            ScrollView {
                LengthPicker(days: $model.lengthDays, startDate: model.startDate)
                    .padding(.top, 22).padding(.bottom, 12)
            }
            if let footnote {
                Text(footnote).font(Font2.sans(12, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.bottom, 10)
            }
            ctaPad(PrimaryButton(title: ctaTitle, action: onNext))
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
                        LinearGradient(colors: [Theme.plum.opacity(0.55), Theme.plum],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "person.2.fill").font(.system(size: 56, weight: .light)).foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 220).frame(maxWidth: .infinity).clipped()

            TypewriterHeadline(lead: "Do it", accent: "together", size: 34, alignment: .center).padding(.top, 8)
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
                PrimaryButton(title: "Partner Up", icon: "person.badge.plus", action: onPartner)
                Button { Haptics.tap(); onSolo() } label: {
                    Text("I prefer solo").font(Font2.sans(16, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous))
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
                PrimaryButton(title: "Continue", action: onNext)
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

// MARK: - 14 Loading

private struct LoadingStep: View {
    var model: OnboardingModel
    var onNext: () -> Void
    @State private var rotate = false
    @State private var done = false

    /// The build-up reads their own answers back while the plan "assembles" —
    /// the quiz pays off here instead of three generic lines.
    private var lines: [String] {
        var l = ["Reading your answers…"]
        if let w = model.wantMost { l.append("Anchoring on \(w.lowercased())…") }
        if let h = model.hardest  { l.append("Planning around \(h.lowercased())…") }
        l.append("Shaping your \(model.lengthDays) days…")
        return l
    }
    private let firstRow = 0.35, rowGap = 0.62

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.ring, lineWidth: 3)
                Circle().trim(from: 0, to: done ? 1 : 0.28)
                    .stroke(AngularGradient(colors: [Theme.berry, Theme.plum, Theme.slate, Theme.berry],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(rotate ? 360 : 0))
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                    .scaleEffect(done ? 1 : 0.3).opacity(done ? 1 : 0)
            }
            .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.berry)
                        Text(line).font(Font2.sans(15, .semibold)).foregroundStyle(Theme.ink.opacity(0.75))
                    }
                    .popIn(delay: firstRow + rowGap * Double(i), from: 0.85)
                }
            }
            Spacer()
        }
        .onAppear { run() }
    }

    private func run() {
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { rotate = true }
        for i in 0..<lines.count {                        // a soft tick as each row lands
            DispatchQueue.main.asyncAfter(deadline: .now() + firstRow + rowGap * Double(i)) { Haptics.light() }
        }
        // The ring completes, the check pops — a beat of "it's done" before moving on.
        let landed = firstRow + rowGap * Double(lines.count - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + landed + 0.55) {
            withAnimation(Motion.pop) { done = true }
            Haptics.success()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + landed + 1.15) { onNext() }
    }
}

// MARK: - 15 Ready / your plan (the sticker card)

private struct ReadyStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var placed = false       // the plan card lands like a sticker being pressed on
    private var congrats: String {
        let n = model.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Congrats." : "Congrats, \(n)."
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(congrats).font(Font2.serif(34, .semibold)).foregroundStyle(Theme.ink)
                SerifHeadline(lead: "You're", accent: "ready", trail: "to start", size: 30, accentColor: Theme.berry)
            }
            .multilineTextAlignment(.center).padding(.top, 10).padding(.horizontal, 28)
            Spacer()
            planCard
                .scaleEffect(placed ? 1 : 1.16)
                .rotationEffect(.degrees(placed ? 0 : 3.5))
                .opacity(placed ? 1 : 0)
            Spacer()
            ctaPad(PrimaryButton(title: "Start now", action: onNext))
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

// MARK: - 16 Make it official (signature — a light-hearted pact, not a contract)

private struct SignPromiseStep: View {
    var model: OnboardingModel
    var onNext: () -> Void
    @State private var strokes: [[CGPoint]] = []

    /// The pact itself — their name and their number, so the signature signs *something*.
    private var pact: String {
        let n = model.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty
            ? "I promise to show up for myself — all \(model.lengthDays) days of it."
            : "I, \(n), promise to show up for myself — all \(model.lengthDays) days of it."
    }
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold))
                    Text("a promise between you and you").font(Font2.sans(12, .bold))
                }.foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.chipFill, in: Capsule())
                    .popIn(delay: 0.3)
                VStack(spacing: 8) {
                    TypewriterHeadline(lead: "Make it", accent: "official", size: 30, alignment: .center)
                    Text("“\(pact)”")
                        .font(Font2.serif(16.5, .medium)).italic()
                        .foregroundStyle(Theme.ink.opacity(0.6))
                        .multilineTextAlignment(.center).padding(.horizontal, 4)
                }
                ZStack(alignment: .bottomTrailing) {
                    SignaturePad(strokes: $strokes).frame(height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ring, lineWidth: 1))
                    Button { strokes = [] } label: {
                        Text("Clear").font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink.opacity(0.5)).underline().padding(10)
                    }
                }
                // The CTA lives INSIDE the card — it wakes up the moment ink lands.
                PrimaryButton(title: "It's official", action: onNext)
                    .disabled(strokes.isEmpty).opacity(strokes.isEmpty ? 0.5 : 1)
                    .scaleEffect(strokes.isEmpty ? 0.98 : 1)
                    .animation(Motion.bouncy, value: strokes.isEmpty)
                Button { onNext() } label: { Text("Skip for now").font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.5)).underline() }
            }
            .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10).padding(.horizontal, 20)
            Spacer()
        }
    }
}

// The paywall (final step) lives in Sources/Premium/PaywallView.swift — it's shared with
// RootGate, which re-shows it if the subscription ever lapses.
