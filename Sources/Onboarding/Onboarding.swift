import SwiftUI
import SwiftData

// MARK: - Model

struct HabitDraft: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var color: HabitColor
    var icon: String
    var photo: String
    init(seed: HabitSeed) { title = seed.title; subtitle = seed.subtitle; color = seed.color; icon = seed.icon; photo = seed.photo }
    init(title: String, subtitle: String, color: HabitColor, icon: String, photo: String = "") {
        self.title = title; self.subtitle = subtitle; self.color = color; self.icon = icon; self.photo = photo
    }
}

@Observable
final class OnboardingModel {
    var name = ""
    var wantMost: String?
    var dailyVibe: String?
    var hardest: String?
    var track: ChallengeTrack = .her
    var trackPicked = false
    var lengthDays = 75
    var startDate = Calendar.current.startOfDay(for: Date())
    var habitDrafts: [HabitDraft] = []

    func pick(_ t: ChallengeTrack) {
        track = t; trackPicked = true
        habitDrafts = t.defaultHabits.map { HabitDraft(seed: $0) }
    }
}

// MARK: - Flow

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @State private var model = OnboardingModel()
    @State private var step = 0
    private let last = 15

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
            if step >= 1 && step != 11 {        // 11 = loading (no back)
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink).frame(width: 38, height: 38)
                        .background(Color.white, in: Circle()).overlay(Circle().stroke(Theme.ring, lineWidth: 1))
                }
            }
            if (4...10).contains(step) {        // quiz → length: setup progress
                ProgressBarThin(value: Double(step - 3) / 7.0, track: Theme.ring, fill: Theme.ink, height: 6)
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
        case 2:  ChipsStep(onNext: next)
        case 3:  NameStep(model: model, onNext: next)
        case 4:  QuizStep(lead: "What do you", accent: "want", trail: "most?",
                          options: ["Feel like myself", "Trust my routine", "Confidence back", "Stay consistent"],
                          photo: "onb_q_want", selection: bind(\.wantMost), onNext: next)
        case 5:  QuizStep(lead: "What's your", accent: "daily", trail: "vibe?",
                          options: ["Slow morning", "Busy but balanced", "Offline evening", "Reset day"],
                          photo: "onb_q_vibe", selection: bind(\.dailyVibe), onNext: next)
        case 6:  QuizStep(lead: "What's the", accent: "hardest?", trail: nil,
                          options: ["Motivation dips", "Food choices", "Better sleep", "Less scrolling"],
                          photo: "onb_q_hard", selection: bind(\.hardest), onNext: next)
        case 7:  ChooseTrackStep(model: model, onNext: next)
        case 8:  CustomizeStep(model: model, onNext: next)
        case 9:  StartDateStep(model: model, onNext: next)
        case 10: LengthStep(model: model, onNext: next)
        case 11: LoadingStep(onNext: next)
        case 12: ReadyStep(model: model, onNext: next)
        case 13: FeedbackStep(onNext: next)
        case 14: SignPromiseStep(onNext: next)
        default: PaywallStep(model: model, onStart: finish)
        }
    }

    private func bind(_ key: ReferenceWritableKeyPath<OnboardingModel, String?>) -> Binding<String?> {
        Binding(get: { model[keyPath: key] }, set: { model[keyPath: key] = $0 })
    }
    private func next() { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = min(step + 1, last) } }
    private func back() { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = max(step - 1, 0) } }

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
        Haptics.success()
    }
}

// CTA buttons are ~75% of the screen width (per the reference), centered.
private func ctaPad<V: View>(_ v: V) -> some View {
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
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
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
            Spacer(minLength: 18)
            TypewriterHeadline(lead: "Become", accent: "that Girl", size: 44, accentColor: Theme.rose, alignment: .center)
                .padding(.horizontal, 20)
            Spacer(minLength: 20)
            ctaPad(VStack(spacing: 14) {
                PrimaryButton(title: "Let's do this", action: onNext)
                Text("Already have an account?").font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.55)).underline()
            })
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
                VStack(spacing: 4) {
                    Text("Welcome to your").font(Font2.serif(28, .semibold)).foregroundStyle(Theme.ink)
                    (Text("next ").font(Font2.serif(28, .semibold)).foregroundColor(Theme.ink)
                     + Text("75 days").font(Font2.serif(28, .bold)).italic().foregroundColor(Theme.coral))
                }
                PrimaryButton(title: "Continue", color: Theme.periwinkle, action: onNext)
            }
        }
    }
}

// MARK: - 2 Friends preview

private struct FriendsPreviewStep: View {
    var onNext: () -> Void
    private let friends = [("Maddy", "@maddy", 75, "friend_maddy", HabitColor.rose),
                           ("Anna", "@anna", 12, "friend_anna", HabitColor.lilac),
                           ("Blake", "@blake", 38, "friend_blake", HabitColor.sage)]
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: -8) {
                ForEach(Array(friends.enumerated()), id: \.offset) { i, f in
                    HStack(spacing: 14) {
                        ZStack {
                            PhotoFill(name: f.3, fallback: f.4.gradient).frame(width: 50, height: 50).clipShape(Circle())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.0).font(Font2.sans(17, .bold)).foregroundStyle(Theme.ink)
                            Text("\(f.1)  ·  day \(f.2)").font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
                    .padding(.horizontal, CGFloat(i == 1 ? 30 : 12)).zIndex(Double(3 - i))
                }
            }
            Spacer()
            OnbBottomCard {
                TypewriterHeadline(lead: "Follow your", accent: "friends", size: 32, accentColor: Theme.coral, alignment: .center)
                PrimaryButton(title: "Continue", color: Theme.sage, action: onNext)
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
                        Theme.plumGradient.frame(height: 380)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).padding(.horizontal, 30)
                AnimatedChips(items: [("heart.fill", "healthy"), ("bolt.fill", "fit"),
                                      ("sparkles", "glowing"), ("scope", "focused"), ("leaf.fill", "calm")])
            }
            Spacer(minLength: 18)
            VStack(spacing: 2) {
                TypewriterHeadline(lead: "Become Her", size: 40, alignment: .center)
                Text("(in 75 days)").font(Font2.serif(24, .medium)).italic().foregroundStyle(Theme.rose)
            }
            Spacer(minLength: 20)
            ctaPad(PrimaryButton(title: "I'm ready", color: Theme.orchid, action: onNext))
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
            ctaPad(PrimaryButton(title: "Continue", color: Theme.orchid, action: onNext)
                .disabled(selection == nil).opacity(selection == nil ? 0.5 : 1)).padding(.top, 12)
        }
        .animation(.easeInOut, value: selection)
    }
}

// MARK: - 8 Choose track (Popular / Custom tabs + clusters)

private struct ChooseTrackStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var tab = 0
    private let joined: [ChallengeTrack: String] = [.her: "+24,872", .strict: "+2,352", .soft: "+7,460", .hot: "+8,321"]
    private let clusterColors: [ChallengeTrack: [HabitColor]] = [
        .her: [.amber, .sage, .blush], .strict: [.berry, .sand, .sky],
        .soft: [.blush, .sand, .lilac], .hot: [.rose, .berry, .amber]]
    private let tracks: [ChallengeTrack] = [.her, .strict, .soft, .hot]

    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "Choose…", size: 38, alignment: .center).padding(.top, 6)
            HStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("Popular").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                    Rectangle().fill(Theme.ink).frame(width: 60, height: 2.5)
                }
                Button { Haptics.select(); model.pick(.custom); onNext() } label: {   // Custom → opens custom screen
                    VStack(spacing: 6) {
                        Text("Custom").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink.opacity(0.35))
                        Rectangle().fill(.clear).frame(width: 60, height: 2.5)
                    }
                }.buttonStyle(.plain)
            }.padding(.top, 12)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(tracks) { t in
                        Button { Haptics.select(); model.pick(t) } label: { trackCard(t) }.buttonStyle(PressableStyle())
                    }
                }.padding(.horizontal, 20).padding(.top, 18)
            }
            ctaPad(PrimaryButton(title: "Let's do it", color: Theme.taupe, action: { if !model.trackPicked { model.pick(model.track) }; onNext() }))
        }
    }

    private func tabButton(_ title: String, _ i: Int) -> some View {
        VStack(spacing: 6) {
            Text(title).font(Font2.sans(16, .bold)).foregroundStyle(tab == i ? Theme.ink : Theme.ink.opacity(0.35))
            Rectangle().fill(tab == i ? Theme.ink : .clear).frame(width: 60, height: 2.5)
        }.onTapGesture { withAnimation { tab = i } }
    }

    private func trackCard(_ t: ChallengeTrack) -> some View {
        let on = model.trackPicked && model.track == t
        return HStack(spacing: 16) {
            ZStack(alignment: .top) {
                TrackCluster(prefix: "track_\(t.rawValue)", colors: clusterColors[t] ?? [.rose, .blush, .sand])
                    .padding(.top, 10)
                Text(joined[t] ?? "").font(Font2.sans(10, .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            Text(t.title).font(Font2.sans(20, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            if on { Circle().fill(Theme.ink).frame(width: 9, height: 9) }
        }
        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(on ? Theme.rose : .clear, lineWidth: 2))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    private var customCard: some View {
        let on = model.trackPicked && model.track == .custom
        return HStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.rose).frame(width: 70)
            VStack(alignment: .leading, spacing: 3) {
                Text("Build your own").font(Font2.sans(19, .heavy)).foregroundStyle(Theme.ink)
                Text("Start from scratch").font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.55))
            }
            Spacer()
            if on { Circle().fill(Theme.ink).frame(width: 9, height: 9) }
        }
        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(on ? Theme.rose : .clear, lineWidth: 2))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

// MARK: - 9 Customize (edit + add task)

private struct CustomizeStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var editing: Int?
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private var title: String { model.track == .custom ? "Custom Challenge" : "\(model.track.title) Challenge" }

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(Font2.serif(28, .semibold)).foregroundStyle(Theme.ink).padding(.top, 6)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(Array(model.habitDrafts.enumerated()), id: \.element.id) { i, d in
                        Button { editing = i } label: { card(d) }.buttonStyle(PressableStyle())
                    }
                }.padding(.horizontal, 20).padding(.top, 16)

                Button {
                    model.habitDrafts.append(HabitDraft(title: "New daily task", subtitle: "Tap to customise", color: .lilac, icon: "plus"))
                    editing = model.habitDrafts.count - 1
                } label: {
                    Text("New Task +").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(.white, in: Capsule()).shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                }.padding(.horizontal, 20).padding(.top, 16)

                testimonials.padding(.top, 22)
            }
            ctaPad(PrimaryButton(title: "Let's go", color: Theme.orchid, action: onNext))
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let i = editing, model.habitDrafts.indices.contains(i) {
                EditTaskSheet(draft: $model.habitDrafts[i], onSave: { Haptics.tap() },
                              onDelete: model.habitDrafts.count > 1 ? { model.habitDrafts.remove(at: i) } : nil)
            }
        }
    }

    private func card(_ d: HabitDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: d.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(d.color.onColor)
            Spacer(minLength: 18)
            Text(d.title).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
            Text(d.subtitle).font(Font2.sans(11.5, .medium)).foregroundStyle(Theme.ink.opacity(0.6)).lineLimit(1)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(d.color.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var testimonials: some View {
        let items: [(handle: String, title: String, body: String)] = [
            ("lily.r", "10/10 recommend", "The aesthetic + the discipline = chef's kiss. On my second round."),
            ("maya.k", "Obsessed", "The honeycomb of photos keeps me going — day 40 and counting."),
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

private struct StartDateStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    @State private var mode = 0
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "When do we", accent: "begin?", size: 32, accentColor: Theme.rose, alignment: .center).padding(.top, 6)
            Spacer()
            Text(bigWord).font(Font2.sans(64, .heavy)).foregroundStyle(Theme.ink).contentTransition(.numericText())
            HStack(spacing: 10) {
                pill("Today", 0); pill("Tomorrow", 1); pill("Custom", 2)
            }.padding(.top, 22)
            if mode == 2 {
                DatePicker("", selection: $model.startDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().tint(Theme.rose).padding(.top, 16)
            } else {
                Text(model.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(Font2.sans(13, .bold)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 12)
            }
            Spacer()
            ctaPad(PrimaryButton(title: "Continue", color: Theme.periwinkle, action: onNext))
        }
        .onAppear { apply(0) }
    }
    private var bigWord: String {
        switch mode { case 0: return "today"; case 1: return "tomorrow"
        default: return model.startDate.formatted(.dateTime.month(.abbreviated).day()) }
    }
    private func pill(_ t: String, _ i: Int) -> some View {
        Button { withAnimation { mode = i }; apply(i); Haptics.select() } label: {
            Text(t).font(Font2.sans(15, .bold)).foregroundStyle(mode == i ? .white : Theme.ink)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(mode == i ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.white), in: Capsule())
                .overlay(Capsule().stroke(Theme.ring, lineWidth: mode == i ? 0 : 1.5))
        }.buttonStyle(.plain)
    }
    private func apply(_ i: Int) {
        let cal = Calendar.current
        if i == 0 { model.startDate = cal.startOfDay(for: Date()) }
        else if i == 1 { model.startDate = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))! }
    }
}

// MARK: - 11 Length

private struct LengthStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    private let presets = [7, 14, 30, 75]
    var body: some View {
        VStack(spacing: 0) {
            TypewriterHeadline(lead: "How long is your", accent: "challenge?", size: 30, accentColor: Theme.rose, alignment: .center).padding(.top, 6)
            Spacer()
            VStack(spacing: 0) {
                Text("\(model.lengthDays)").font(Font2.sans(78, .heavy)).foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())                 // odometer
                    .animation(.snappy(duration: 0.25), value: model.lengthDays)
                Text("days").font(Font2.sans(17, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
            }
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { p in
                    Button { withAnimation { model.lengthDays = p }; Haptics.select() } label: {
                        Text("\(p)").font(Font2.sans(15, .bold)).foregroundStyle(model.lengthDays == p ? .white : Theme.ink)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(model.lengthDays == p ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.white), in: Capsule())
                            .overlay(Capsule().stroke(Theme.ring, lineWidth: model.lengthDays == p ? 0 : 1.5))
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 20)
            // "Custom" pill — highlights when the value isn't one of the presets
            Text("Custom")
                .font(Font2.sans(15, .bold)).foregroundStyle(presets.contains(model.lengthDays) ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(presets.contains(model.lengthDays) ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.ink), in: Capsule())
                .overlay(Capsule().stroke(Theme.ring, lineWidth: presets.contains(model.lengthDays) ? 1.5 : 0))
                .padding(.horizontal, 30).padding(.top, 10)
            Slider(value: Binding(get: { Double(model.lengthDays) }, set: { model.lengthDays = Int($0.rounded()) }), in: 1...75, step: 1)
                .tint(Theme.sage).padding(.horizontal, 30).padding(.top, 16)
            Text(range).font(Font2.sans(13, .medium)).foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 6)
            Spacer()
            ctaPad(PrimaryButton(title: "Continue", color: Theme.sage, action: onNext))
        }
    }
    private var range: String {
        let end = Calendar.current.date(byAdding: .day, value: model.lengthDays - 1, to: model.startDate) ?? model.startDate
        return "\(model.startDate.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

// MARK: - 12 Partner up

private struct PartnerUpStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            if AppImage.exists("onb_together") {
                PhotoFill(name: "onb_together").frame(height: 220).frame(maxWidth: .infinity).clipped()
            } else {
                Image(systemName: "person.2.fill").font(.system(size: 60, weight: .light)).foregroundStyle(Theme.rose).frame(height: 220)
            }
            TypewriterHeadline(lead: "Do it", accent: "together", size: 34, accentColor: Theme.rose, alignment: .center).padding(.top, 6)
            Text("Add your friends, see their progress, and keep each other accountable through the challenge.")
                .font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.55))
                .multilineTextAlignment(.center).padding(.horizontal, 36).padding(.top, 8)
            Text("teaming up you're 24% more likely to finish")
                .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.chipFill, in: Capsule()).padding(.top, 14)
            Spacer()
            ctaPad(VStack(spacing: 10) {
                PrimaryButton(title: "Partner Up", icon: "person.badge.plus", color: Theme.coral, action: onNext)
                Button { onNext() } label: {
                    Text("I prefer solo").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(.white, in: Capsule()).overlay(Capsule().stroke(Theme.ring, lineWidth: 1.5))
                }
            })
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

// MARK: - 14 Ready

private struct ReadyStep: View {
    @Bindable var model: OnboardingModel
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 6) {
                (Text("You're ready, ").font(Font2.serif(34, .semibold)).foregroundColor(Theme.ink)
                 + Text(model.name.isEmpty ? "you" : model.name).font(Font2.serif(34, .bold)).italic().foregroundColor(Theme.rose)
                 + Text(".").font(Font2.serif(34, .semibold)).foregroundColor(Theme.ink))
                (Text("Your ").font(Font2.serif(26, .medium)).foregroundColor(Theme.ink)
                 + Text("\(model.lengthDays)-day").font(Font2.serif(26, .semibold)).italic().foregroundColor(Theme.ink)
                 + Text(" mission starts ").font(Font2.serif(26, .medium)).foregroundColor(Theme.ink)
                 + Text("now").font(Font2.serif(26, .bold)).italic().foregroundColor(Theme.rose)
                 + Text(".").font(Font2.serif(26, .medium)).foregroundColor(Theme.ink))
                    .multilineTextAlignment(.center)
            }.padding(.horizontal, 28)
            if AppImage.exists("onb_ready") {
                PhotoFill(name: "onb_ready").frame(height: 280).frame(maxWidth: .infinity).clipped().padding(.top, 20)
            }
            Spacer()
            ctaPad(PrimaryButton(title: "Let's begin", color: Theme.taupe, action: onNext))
        }
    }
}

// MARK: - 15 Feedback

private struct FeedbackStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            TypewriterHeadline(lead: "We'd love to hear", accent: "what", trail: "you think.", size: 32, accentColor: Theme.ink, alignment: .center)
                .padding(.horizontal, 30)
            Spacer()
            ctaPad(PrimaryButton(title: "Continue", color: Theme.periwinkle, action: onNext))
        }
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
            .shadow(color: .black.opacity(0.06), radius: 16, y: 8).padding(.horizontal, 20)
            Spacer()
        }
    }
}

// MARK: - 17 Paywall (UI stub)

private struct PaywallStep: View {
    @Bindable var model: OnboardingModel
    var onStart: () -> Void
    @State private var plan = 0
    private let plans = [("Yearly", "$49.99/year", "Save 88%"), ("Monthly", "$14.99/month", ""), ("Weekly", "$7.99/week", "")]
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text("Become Her in \(model.lengthDays) days").font(Font2.serif(30, .semibold)).foregroundStyle(Theme.ink)
                        Text("Join 30,000+ women").font(Font2.serif(26, .semibold)).foregroundStyle(Theme.ink)
                    }.multilineTextAlignment(.center).padding(.top, 10)
                    VStack(spacing: 6) {
                        ForEach(["Achieve aesthetic", "Join community", "Stay accountable"], id: \.self) { b in
                            Label(b, systemImage: "checkmark.circle.fill").font(Font2.sans(14, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
                        }
                    }.padding(.top, 12)
                    VStack(spacing: 10) {
                        ForEach(Array(plans.enumerated()), id: \.offset) { i, p in
                            Button { plan = i; Haptics.select() } label: { planRow(i, p) }.buttonStyle(.plain)
                        }
                    }.padding(.top, 16)
                }.padding(.horizontal, 22)
            }
            ctaPad(VStack(spacing: 10) {
                PrimaryButton.ink("Become Her", action: onStart)
                HStack(spacing: 18) { Text("Terms"); Text("Restore"); Text("Privacy") }
                    .font(Font2.sans(11, .medium)).foregroundStyle(Theme.ink.opacity(0.4))
            }).padding(.top, 8)
        }
    }
    private func planRow(_ i: Int, _ p: (String, String, String)) -> some View {
        let on = plan == i
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(on ? Theme.rose : Theme.ring, lineWidth: 2).frame(width: 24, height: 24)
                if on { Circle().fill(Theme.rose).frame(width: 14, height: 14) }
            }
            Text(p.0).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
            if !p.2.isEmpty {
                Text(p.2).font(Font2.sans(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.sageBadge, in: Capsule())
            }
            Spacer()
            Text(p.1).font(Font2.sans(15, .heavy)).foregroundStyle(Theme.ink)
        }
        .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? Theme.ink : Theme.ring, lineWidth: on ? 2 : 1))
    }
}
