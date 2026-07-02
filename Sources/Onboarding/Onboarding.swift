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
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
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
                          photo: "onb_q_want", color: Theme.taupe, selection: bind(\.wantMost), onNext: next)
        case 6:  QuizStep(lead: "What's your", accent: "daily", trail: "vibe?",
                          options: ["Calm & slow", "Busy & driven", "Social & fun", "Quiet & focused"],
                          photo: "onb_q_vibe", color: Theme.coral, selection: bind(\.dailyVibe), onNext: next)
        case 7:  QuizStep(lead: "What's the", accent: "hardest?", trail: nil,
                          options: ["Staying consistent", "Sugar cravings", "Enough sleep", "Screen time"],
                          photo: "onb_q_hard", color: Theme.periwinkle, selection: bind(\.hardest), onNext: next)
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
    private func next() { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = min(step + 1, last) } }
    private func back() { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = max(step - 1, 0) } }
    private func skip(to s: Int) { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = min(max(s, 0), last) } }

    private func finish() {
        if model.habitDrafts.isEmpty { model.pick(model.track) }
        let c = Challenge(track: model.track, lengthDays: model.lengthDays, startDate: model.startDate, ownerName: model.name)
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
                Text("+24,872 joined").font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white, in: Capsule()).shadow(color: .black.opacity(0.1), radius: 8, y: 4).padding(.top, 6)
            }
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Become", accent: "that Girl", size: 40, accentColor: Theme.rose, alignment: .center)
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
            MiniPhonePreview()
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Welcome to your next", accent: "75 days", size: 28, accentColor: Theme.coral, alignment: .center)
                PrimaryButton(title: "Continue", color: Theme.periwinkle, action: onNext)
            }
        }
    }
}

// MARK: - 2 Friends preview

private struct FriendsPreviewStep: View {
    var onNext: () -> Void
    // Same card language as the real Friends tab (name · day · done/total · progress), no handles.
    private struct Peek { let name: String; let day: Int; let done: Int; let total: Int; let photo: String; let color: HabitColor }
    private let peeks = [Peek(name: "Maddy", day: 75, done: 6, total: 6, photo: "friend_maddy", color: .rose),
                         Peek(name: "Anna",  day: 12, done: 3, total: 5, photo: "friend_anna",  color: .lilac),
                         Peek(name: "Blake", day: 38, done: 4, total: 6, photo: "friend_blake", color: .sage)]
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                ForEach(Array(peeks.enumerated()), id: \.offset) { _, f in card(f) }
            }
            .padding(.horizontal, 22)
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Follow your", accent: "friends", size: 32, accentColor: Theme.sage, alignment: .center)
                PrimaryButton(title: "Continue", color: Theme.sage, action: onNext)
            }
        }
    }

    private func card(_ f: Peek) -> some View {
        let fraction = Double(f.done) / Double(f.total)
        let complete = f.done >= f.total
        return HStack(spacing: 14) {
            PhotoFill(name: f.photo, fallback: f.color.gradient).frame(width: 48, height: 48).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(f.name).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("Day \(f.day) · \(f.done)/\(f.total) done")
                    .font(Font2.sans(12, .medium)).foregroundStyle(Theme.textSecondary)
                ProgressCapsule(fraction: fraction, accent: Theme.sage)
            }
            Spacer(minLength: 8)
            if complete {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 24)).foregroundStyle(Theme.sage)
            } else {
                Text("\(Int(fraction * 100))%").font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
            }
        }
        .padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
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
                        Theme.plumGradient.frame(height: 380)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).padding(.horizontal, 30)
                AnimatedChips(items: [("heart.fill", "healthy"), ("bolt.fill", "fit"),
                                      ("sparkles", "glowing"), ("scope", "focused"), ("leaf.fill", "calm")])
            }
            Spacer(minLength: 18)
            OnbBottomCard {
                VStack(spacing: 2) {
                    TypewriterHeadline(lead: "Become Her", size: 36, alignment: .center)
                    Text("(in 75 days)").font(Font2.serif(22, .medium)).italic().foregroundStyle(Theme.coral)
                }
                PrimaryButton(title: "I'm ready", color: Theme.sage, action: onNext)
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
            Rectangle().fill(Theme.ring).frame(width: 220, height: 1.5).padding(.top, 6)
            Spacer()
            if AppImage.exists("onb_name") {
                PhotoFill(name: "onb_name").frame(height: 220).frame(maxWidth: .infinity).clipped()
            }
            ctaPad(PrimaryButton(title: "Continue", color: Theme.orchid, action: { focused = false; onNext() })
                .disabled(empty).opacity(empty ? 0.5 : 1)).padding(.top, 12)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true } }
    }
}

// MARK: - 5–7 Quiz

private struct QuizStep: View {
    let lead: String; let accent: String; let trail: String?
    let options: [String]; let photo: String
    var color: Color = Theme.orchid
    @Binding var selection: String?
    var onNext: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypewriterHeadline(lead: lead, accent: accent, trail: trail, size: 32, accentColor: Theme.ink, accentItalic: false)
                .padding(.horizontal, 24).padding(.top, 6)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(options, id: \.self) { opt in
                    OptionPill(text: opt, selected: selection == opt) { selection = opt }
                }
            }.padding(.horizontal, 24).padding(.top, 22)
            Spacer()
            if selection != nil, AppImage.exists(photo) {
                PhotoFill(name: photo).frame(height: 200).frame(maxWidth: .infinity).clipped().transition(.opacity)
            }
            ctaPad(PrimaryButton(title: "Continue", color: color, action: onNext)
                .disabled(selection == nil).opacity(selection == nil ? 0.5 : 1)).padding(.top, 12)
        }
        .animation(.easeInOut, value: selection)
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
                    ForEach(ChallengeTrack.catalog) { t in
                        Button { Haptics.select(); model.pick(t); onNext() } label: { ChallengeStripCard(track: t) }
                            .buttonStyle(PressableStyle())
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.track.title).font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .center)
                    TaskListEditor(track: model.track,
                                   items: model.habitDrafts.map { ($0.title, $0.color) },
                                   onAdd: addTask, onEdit: { editing = $0 })
                    testimonials.padding(.top, 6)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            }
            ctaPad(PrimaryButton(title: "Continue", color: Theme.sage, action: onNext))
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

    private var testimonials: some View {
        let items: [(handle: String, title: String, body: String)] = [
            ("lily.r", "10/10 recommend", "The aesthetic + the discipline = chef's kiss. On my second round."),
            ("maya.k", "Obsessed", "The proof photos keep me going — day 40 and counting."),
            ("anna.b", "Actually stuck with it", "First challenge I've ever finished. The widget is everything."),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                    HStack(spacing: 12) {
                        PhotoFill(name: "testimonial_\(i + 1)", fallback: HabitColor.blush.gradient)
                            .frame(width: 40, height: 40).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink)
                            Text(t.body).font(Font2.sans(11.5, .medium)).foregroundStyle(Theme.ink.opacity(0.6)).lineLimit(2)
                            Text("@\(t.handle)").font(Font2.sans(10, .medium)).foregroundStyle(Theme.ink.opacity(0.4))
                        }
                    }
                    .padding(14).frame(width: 264, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                }
            }.padding(.horizontal, 20)
        }
    }
}

// MARK: - 10 Start date

struct StartDateStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var mode = 0
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "When do we", accent: "begin?", size: 32, accentColor: Theme.rose, alignment: .center).padding(.top, 6)
            Spacer()
            Text(bigWord).font(Font2.sans(64, .heavy)).foregroundStyle(Theme.ink).contentTransition(.numericText())
            HStack(spacing: 10) {
                ForEach(Array(["Today", "Tomorrow", "Custom"].enumerated()), id: \.offset) { i, t in
                    SelectPill(text: t, selected: mode == i, hPad: 20, vPad: 12) {
                        withAnimation { mode = i }; apply(i)
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
            ctaPad(PrimaryButton(title: "Continue", color: Theme.orchid, action: onNext))
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
            LengthPicker(days: $model.lengthDays, startDate: model.startDate, showsCustomBadge: true)
            Spacer()
            if let footnote {
                Text(footnote).font(Font2.sans(12, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.bottom, 10)
            }
            ctaPad(PrimaryButton(title: ctaTitle, color: Theme.taupe, action: onNext))
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
                    PhotoFill(name: "onb_together")
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.sage.opacity(0.55), Theme.sage],
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
            Text("teaming up you're 24% more likely to finish")
                .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white, in: Capsule()).shadow(color: .black.opacity(0.06), radius: 6, y: 3).padding(.top, 14)
            Spacer()
            ctaPad(VStack(spacing: 10) {
                PrimaryButton(title: "Partner Up", icon: "person.badge.plus", color: Theme.coral, action: onPartner)
                Button { Haptics.tap(); onSolo() } label: {
                    Text("I prefer solo").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(.white, in: Capsule()).overlay(Capsule().stroke(Theme.ring, lineWidth: 1.5))
                }
            })
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
            Text("teaming up you're 24% more likely to finish!")
                .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white, in: Capsule()).shadow(color: .black.opacity(0.06), radius: 6, y: 3).padding(.top, 16)
            Spacer()
            InviteTicket(name: model.name, code: social.myCode).padding(.horizontal, 22)
            Spacer()
            HStack(spacing: 12) {
                PrimaryButton(title: "Continue", color: Theme.periwinkle, action: onNext)
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
    private let lines = ["Saving your daily mission…", "Pinning your start date…", "Almost ready…"]
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Circle().trim(from: 0, to: 0.28)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 78, height: 78)
                .rotationEffect(.degrees(rotate ? 360 : 0))
            Text(lines[min(idx, lines.count - 1)]).font(Font2.serif(20, .medium)).italic().foregroundStyle(Theme.ink.opacity(0.7))
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { rotate = true }
            for i in 1..<lines.count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.85 * Double(i)) { withAnimation { idx = i } } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { onNext() }
        }
    }
}

// MARK: - 12 Ready / your plan (the sticker card, like 1505)

private struct ReadyStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Congrats.").font(Font2.serif(34, .semibold)).foregroundStyle(Theme.ink)
                SerifHeadline(lead: "You're", accent: "ready", trail: "to start", size: 30, accentColor: Theme.rose)
            }
            .multilineTextAlignment(.center).padding(.top, 10).padding(.horizontal, 28)
            Spacer()
            planCard
            Spacer()
            ctaPad(PrimaryButton(title: "Start now", color: Theme.periwinkle, action: onNext))
        }
    }

    private var planCard: some View {
        let end = Calendar.current.date(byAdding: .day, value: model.lengthDays - 1, to: model.startDate) ?? model.startDate
        let range = "\(model.startDate.formatted(.dateTime.month(.abbreviated).day()))  →  \(end.formatted(.dateTime.month(.abbreviated).day()))".lowercased()
        return VStack(alignment: .leading, spacing: 12) {
            (Text("day").font(Font2.serif(26, .medium)).italic().foregroundColor(Theme.ink)
             + Text(" one").font(Font2.serif(26, .semibold)).foregroundColor(Theme.ink))
            Text(range).font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.habitDrafts.enumerated()), id: \.element.id) { i, d in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(i + 1)").font(Font2.serif(17, .medium)).foregroundStyle(Theme.ink.opacity(0.6))
                            .frame(width: 18, alignment: .leading)
                        Text(d.title).font(Font2.sans(13.5, .semibold)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }.padding(.top, 2)
            Divider().padding(.top, 4)
            HStack {
                Text(model.track.title.uppercased()).font(Font2.sans(9, .bold)).tracking(1).foregroundStyle(Theme.ink.opacity(0.35))
                Spacer()
                Text("BY 75 HER").font(Font2.sans(9, .bold)).tracking(1).foregroundStyle(Theme.ink.opacity(0.35))
            }
        }
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
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
                    Text("89% of girlies who signed, finished").font(Font2.sans(12, .bold))
                }.foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.chipFill, in: Capsule())
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
                // I commit / Skip live INSIDE the card
                PrimaryButton(title: "I commit", color: Theme.sage, action: onNext)
                    .disabled(strokes.isEmpty).opacity(strokes.isEmpty ? 0.5 : 1)
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
