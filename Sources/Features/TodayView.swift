import SwiftUI
import SwiftData
import PhotosUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @Environment(CelebrationCenter.self) private var celebration
    @State private var editing = false
    @State private var dayIndex = 0
    @State private var celebratedDays: Set<Int> = []

    private var challenge: Challenge? { challenges.first }

    var body: some View {
        VStack(spacing: 0) {
            if let c = challenge {
                TabHeader(day: min(max(dayIndex, 0), max(c.lengthDays - 1, 0)) + 1) {
                    CircleIconButton(icon: "pencil") { editing = true }
                }
                RulerSlider(value: Binding(get: { min(max(dayIndex, 0), max(c.lengthDays - 1, 0)) + 1 },
                                           set: { dayIndex = $0 - 1 }),
                            range: 1...max(c.lengthDays, 1), accent: Theme.clay,
                            showValue: false, showLabels: false)
                    .padding(.horizontal, 30).padding(.top, 14)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(c.habitsOrdered.enumerated()), id: \.element.id) { i, h in
                            HabitRow(habit: h, date: date(c)) { handleAction(c) }
                                .staggeredAppear(index: i)
                            if i < c.habitsOrdered.count - 1 { Divider().padding(.leading, 112) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 30)
                    .animation(Motion.snappy, value: dayIndex)
                }
                .scrollIndicators(.hidden)
                // Rows melt into the paper instead of clipping at the scroll edges.
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.025),
                                           .init(color: .black, location: 0.97),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .onAppear { if dayIndex == 0 { dayIndex = max(c.currentDay - 1, 0) } }
            } else {
                Spacer()
                ContentUnavailableView {
                    Label {
                        Text("No challenge yet")
                    } icon: {
                        Image(systemName: "checklist").symbolEffect(.pulse)
                    }
                }
                Spacer()
            }
        }
        .her75Background(Theme.clay)
        .sheet(isPresented: $editing) { if let c = challenge { EditHabitsSheet(challenge: c) } }
        .task {
            await SocialStore.shared.bootstrap()
            if let c = challenge { await SocialStore.shared.publishStatus(for: c) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Missions toggled from the widget land while we're suspended — republish on return
            // so friends see that progress without waiting for an in-app action. (publishStatus
            // is throttled: nothing changed → no CloudKit write.)
            guard phase == .active, let c = challenge else { return }
            Task { await SocialStore.shared.publishStatus(for: c) }
        }
    }

    private func date(_ c: Challenge) -> Date {
        let idx = min(max(dayIndex, 0), max(c.lengthDays - 1, 0))
        return Calendar.current.date(byAdding: .day, value: idx, to: Calendar.current.startOfDay(for: c.startDate)) ?? c.startDate
    }

    // Fire the crumple-to-trash celebration only on the TRANSITION to all-done for a day,
    // so logging a photo (or re-toggling) after everything's already done doesn't replay it.
    private func handleAction(_ c: Challenge) {
        let d = date(c)
        let idx = min(max(dayIndex, 0), max(c.lengthDays - 1, 0))
        let habits = c.habitsOrdered
        let allDone = !habits.isEmpty && habits.allSatisfy { $0.completion(on: d) != nil }
        if allDone {
            if !celebratedDays.contains(idx) {
                celebratedDays.insert(idx)
                celebration.finale = idx + 1 >= c.lengthDays
                celebration.info = CelebrationInfo(day: idx + 1,
                                                   tasks: habits.map(\.title),
                                                   start: c.startDate,
                                                   days: c.lengthDays,
                                                   title: c.displayTitle)
            }
        } else {
            celebratedDays.remove(idx)
        }
        // Keep my shared status current so friends see today's progress.
        Task { await SocialStore.shared.publishStatus(for: c) }
    }
}

// MARK: - Habit row — photo card (left) · name (center, strikethrough) · check circle (right)

struct HabitRow: View {
    let habit: Habit
    let date: Date
    var onAction: () -> Void = {}
    @Environment(\.modelContext) private var context
    @State private var photoItem: PhotosPickerItem?
    @State private var checkCenter: CGPoint = .zero
    @State private var rippleTrigger = 0

    private var done: Bool { habit.completion(on: date) != nil }
    private var thumb: UIImage? {
        guard let data = habit.completion(on: date)?.photoData else { return nil }
        return ImageProcessing.thumbnail(data, maxPixel: 170)
    }

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    if let img = thumb {
                        Image(uiImage: img).resizable().scaledToFill()
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        Theme.chipFill
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink.opacity(0.25))
                    }
                }
                .frame(width: 84, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .animation(Motion.bouncy, value: thumb != nil)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(Font2.sans(16, .bold))
                    .foregroundStyle(done ? Theme.ink.opacity(0.4) : Theme.ink)
                    .strikethrough(done, color: Theme.ink.opacity(0.5))
                    .lineLimit(2)
                    .animation(Motion.snappy, value: done)
                if let comp = habit.completion(on: date) {
                    Text(comp.loggedAt.formatted(date: .omitted, time: .shortened))
                        .font(Font2.sans(11, .semibold)).foregroundStyle(Theme.ink.opacity(0.4))
                }
            }

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                if !done { rippleTrigger += 1 }     // the liquid pulse fires on check, not uncheck
                HabitActions.toggle(habit, on: date, context: context)
                onAction()
            } label: {
                CheckCircle(done: done)
            }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGPoint.self) { proxy in
                let f = proxy.frame(in: .named("habitRow"))
                return CGPoint(x: f.midX, y: f.midY)
            } action: { checkCenter = $0 }
        }
        .padding(.vertical, 14)
        .coordinateSpace(.named("habitRow"))
        .rippleOnTap(at: checkCenter, trigger: rippleTrigger)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        HabitActions.setPhoto(habit, on: date, photo: data, context: context)
                        Haptics.success()
                        onAction()
                    }
                }
            }
        }
    }
}

// MARK: - Check circle — ink fill pops in, the checkmark draws itself on

private struct CheckCircle: View {
    var done: Bool
    var body: some View {
        ZStack {
            Circle().fill(Theme.ink).scaleEffect(done ? 1 : 0.4).opacity(done ? 1 : 0)
            Circle().stroke(done ? Theme.ink : Theme.ring, lineWidth: 2)
            CheckShape()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 10)
        }
        .frame(width: 28, height: 28)
        .animation(Motion.pop, value: done)
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

// MARK: - Day celebration — poppers → sticky note crumples into the bin → shareable sticker

/// What a finished day needs to render its celebration + shareable sticker.
struct CelebrationInfo: Equatable {
    let day: Int
    let tasks: [String]
    let start: Date
    let days: Int          // challenge length (for the date range)
    let title: String
}

/// Hoisted to RootView so the celebration can blur and cover the whole screen (incl. the tab bar).
@Observable final class CelebrationCenter {
    var info: CelebrationInfo? = nil
    var finale = false      // the celebrated day was the challenge's last
}

/// A hands-off sequence: confetti poppers fire, the day sticky note lands and then
/// auto-crumples into the dustbin, and the finished-day sticker card slides up — with a
/// close button and "Save today's sticker".
struct DayCelebration: View {
    let info: CelebrationInfo
    var onDone: () -> Void

    @State private var show = false
    @State private var exiting = false          // note crumples, shrinks, and drops into the trash
    @State private var crumple: CGFloat = 0
    @State private var swallowed = false        // trash squash-and-stretch as it "eats" the note
    @State private var phase: Phase = .intro
    @State private var stickerPlaced = false    // the sticker "slaps" into place, like onboarding
    @State private var stickerImage: Image?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case intro, sticker }
    private var range: String { challengeRangeText(start: info.start, days: info.days) }

    var body: some View {
        ZStack {
            if phase == .intro {
                ConfettiBurst().allowsHitTesting(false)
                intro
            } else {
                sticker.transition(.opacity)   // the card does its own scale slap
            }
        }
        .onAppear { runIntro() }
    }

    // MARK: Intro (note lands, then auto-crumples into the bin)

    private var intro: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()
                note
                    .shimmerOnce(delay: 0.5)
                    .modifier(CrumpleEffect(progress: crumple))
                    .scaleEffect(exiting ? 0.16 : (show ? 1 : 0.4))
                    .rotationEffect(.degrees(exiting ? 22 : (show ? 0 : -5)))
                    .offset(y: exiting ? geo.size.height / 2 - 130 : 0)
                    .opacity(show && !swallowed ? 1 : 0)
                Spacer()
                Image(systemName: "trash.fill")
                    .font(.system(size: 80, weight: .regular))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .scaleEffect(x: swallowed ? 1.1 : 1, y: swallowed ? 0.86 : 1, anchor: .bottom)
                    .animation(Motion.bouncy, value: swallowed)
                    .padding(.bottom, 56)
                    .opacity(show ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // GeometryReader pins top-left; fill so it centers
        }
    }

    // The sticky note — same paper as the task tiles, day number in serif italic.
    private var note: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.olive.gradient)
                .frame(width: 188, height: 188)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 14)
            Text("\(info.day)")
                .font(Font2.serif(112, .medium)).italic()
                .foregroundStyle(Theme.ink)
        }
    }

    private func runIntro() {
        // Success, then two light ticks timed to the corner poppers.
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { Haptics.light() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { Haptics.light() }
        withAnimation(Motion.bouncy) { show = true }

        if reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { revealSticker() }
            return
        }
        // Land, hold a beat, then crumple → drop → the bin gulps → reveal the sticker.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.55)) { exiting = true; crumple = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                swallowed = true
                Haptics.rigid()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { revealSticker() }
            }
        }
    }

    private func revealSticker() {
        renderSticker()
        withAnimation(Motion.gentle) { phase = .sticker }
        // The card slaps into place a beat after it fades in, like the onboarding plan card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(Motion.bouncy) { stickerPlaced = true }
            Haptics.rigid()
        }
    }

    // MARK: Sticker (the finished-day receipt + save + close)

    private var sticker: some View {
        VStack(spacing: 0) {
            Spacer()
            DayStickerCard(dayWords: dayInWords(info.day), range: range,
                           tasks: info.tasks, challengeTitle: info.title, checked: true)
                .padding(.horizontal, 42)
                .scaleEffect(stickerPlaced ? 1 : 1.12)
                .rotationEffect(.degrees(stickerPlaced ? 0 : 3))
            Spacer()
            saveButton.ctaWidth().padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            CircleIconButton(icon: "xmark") { onDone() }
                .padding(.top, 54).padding(.trailing, 20)
        }
    }

    // Styled like PrimaryButton, but a ShareLink so it opens the share/save sheet directly.
    @ViewBuilder private var saveButton: some View {
        if let stickerImage {
            ShareLink(item: stickerImage,
                      preview: SharePreview("Day \(info.day) · \(info.title)", image: stickerImage)) {
                saveLabel
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        } else {
            saveLabel.opacity(0.4)
        }
    }

    private var saveLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line").font(.system(size: 16, weight: .bold))
            Text("Save today's sticker").font(Font2.sans(17, .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 17)
        .background(Theme.olive, in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous))
        .shadow(color: Theme.olive.opacity(0.30), radius: 10, x: 0, y: 5)
    }

    /// Render the sticker to a standalone image (on paper) for sharing / saving to Photos.
    @MainActor private func renderSticker() {
        let card = DayStickerCard(dayWords: dayInWords(info.day), range: range,
                                  tasks: info.tasks, challengeTitle: info.title, checked: true)
            .padding(26)
            .frame(width: 360)
            .background(Theme.paper)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage { stickerImage = Image(uiImage: ui) }
    }
}

// MARK: - Confetti — two corner poppers, one Canvas, real physics

struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date? = nil
    @State private var finished = false

    private static let palette: [Color] = [Theme.clay, Theme.mist, Theme.olive, Theme.mauve, Theme.sand]
    private static let pieceCount = 120
    private static let gravity: CGFloat = 1350

    var body: some View {
        TimelineView(.animation(paused: finished || reduceMotion)) { tl in
            Canvas { ctx, size in
                guard let start else { return }
                let t = tl.date.timeIntervalSince(start)
                for i in 0..<Self.pieceCount { draw(piece: i, at: t, in: size, ctx: ctx) }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            start = Date()
            // Longest delay + lifetime ≈ 3.4s; stop the TimelineView shortly after.
            Task { try? await Task.sleep(for: .seconds(3.6)); finished = true }
        }
    }

    // Deterministic pseudo-random so pieces don't reshuffle between frames.
    private func rnd(_ seed: Int, _ salt: Int) -> CGFloat {
        let x = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(x - x.rounded(.down))
    }

    private func draw(piece i: Int, at t: TimeInterval, in size: CGSize, ctx: GraphicsContext) {
        let leftPopper = i % 2 == 0
        let delay = Double(rnd(i, 1)) * 0.35 + (leftPopper ? 0 : 0.12)
        let te = CGFloat(t - delay)
        guard te > 0 else { return }

        // Launch: up and inward from a bottom corner, with spread.
        let origin = CGPoint(x: leftPopper ? size.width * 0.05 : size.width * 0.95, y: size.height + 10)
        let baseAngle: CGFloat = leftPopper ? -1.20 : -1.94          // radians; ±~69° from vertical
        let angle = baseAngle + (rnd(i, 2) - 0.5) * 0.66
        let speed = 950 + rnd(i, 3) * 650
        let vx = cos(angle) * speed
        let vy = sin(angle) * speed

        // Flight: ballistic + side-to-side flutter as the piece sheds speed.
        let flutter = sin(te * (3 + rnd(i, 4) * 3) + rnd(i, 5) * 6) * 26 * min(te, 1.4)
        let x = origin.x + vx * te + flutter
        let y = origin.y + vy * te + 0.5 * Self.gravity * te * te
        guard y < size.height + 30 else { return }

        let life = 2.4 + Double(rnd(i, 6)) * 0.6
        let alpha = t - delay > life - 0.5 ? max(0, (life - (t - delay)) / 0.5) : 1
        guard alpha > 0 else { return }

        // Tumble: rotation + the width collapsing through 0 reads as a 3D flip.
        let w = (7 + rnd(i, 7) * 7) * abs(cos(te * (4 + rnd(i, 8) * 4)))
        let h = 10 + rnd(i, 9) * 9
        var p = ctx
        p.translateBy(x: x, y: y)
        p.rotate(by: .radians(Double(te) * (2 + Double(rnd(i, 10)) * 6)))
        p.opacity = alpha
        p.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 2),
               with: .color(Self.palette[i % Self.palette.count]))
    }
}

// MARK: - Shared minimal header (avatar + day badge + optional trailing button)

struct TabHeader<Trailing: View>: View {
    let day: Int
    var showAvatar = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top) {
            if showAvatar {
                ZStack(alignment: .bottom) {
                    ProfileAvatar()
                    dayPill.offset(y: 13)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 22).padding(.top, 10)
    }

    private var dayPill: some View {
        Text("day \(day)")
            .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .animation(Motion.snappy, value: day)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }
}

// MARK: - Edit tasks sheet (the pencil)

struct EditHabitsSheet: View {
    let challenge: Challenge
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Habit?

    var body: some View {
        NavigationStack {
            ScrollView {
                TaskListEditor(track: challenge.track,
                               items: challenge.habitsOrdered.map { ($0.title, $0.color) },
                               onAdd: addTask, onEdit: { editing = challenge.habitsOrdered[$0] })
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }
            .her75Background()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(challenge.displayTitle).font(Font2.serif(20, .semibold)).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { h in
                // The shared sticky-note editor, driving a LIVE habit through a draft binding.
                EditTaskSheet(draft: draftBinding(h),
                              onSave: { Haptics.tap() },
                              onDelete: challenge.habitsOrdered.count > 1
                                  ? { context.delete(h); try? context.save() } : nil)
            }
        }
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
    }

    /// Live Habit ⇄ HabitDraft adapter: every edit writes straight through to the model.
    private func draftBinding(_ h: Habit) -> Binding<HabitDraft> {
        Binding(
            get: { HabitDraft(title: h.title, subtitle: h.subtitle, color: h.color, icon: h.icon, photo: h.photoName) },
            set: { d in
                h.title = d.title; h.subtitle = d.subtitle; h.colorRaw = d.color.rawValue
                try? context.save()
            })
    }

    private func addTask() {
        let h = Habit(title: "New daily task", subtitle: "", color: .sage, icon: "plus", order: challenge.habits.count)
        h.challenge = challenge
        context.insert(h)
        try? context.save()
        editing = h
    }
}

