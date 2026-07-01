import SwiftUI
import SwiftData
import PhotosUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
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
                    Button { editing = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                }
                RulerSlider(value: Binding(get: { min(max(dayIndex, 0), max(c.lengthDays - 1, 0)) + 1 },
                                           set: { dayIndex = $0 - 1 }),
                            range: 1...max(c.lengthDays, 1), accent: Theme.coral,
                            showValue: false, showLabels: false)
                    .padding(.horizontal, 30).padding(.top, 14)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(c.habitsOrdered.enumerated()), id: \.element.id) { i, h in
                            HabitRow(habit: h, date: date(c)) { handleAction(c) }
                            if i < c.habitsOrdered.count - 1 { Divider().padding(.leading, 112) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .onAppear { if dayIndex == 0 { dayIndex = max(c.currentDay - 1, 0) } }
            } else {
                Spacer()
                ContentUnavailableView("No challenge yet", systemImage: "checklist")
                Spacer()
            }
        }
        .her75Background()
        .sheet(isPresented: $editing) { if let c = challenge { EditHabitsSheet(challenge: c) } }
        .task {
            await SocialStore.shared.bootstrap()
            if let c = challenge { await SocialStore.shared.publishStatus(for: c) }
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
                celebration.day = idx + 1
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
                    } else {
                        Theme.chipFill
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink.opacity(0.25))
                    }
                }
                .frame(width: 84, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(Font2.sans(16, .bold))
                    .foregroundStyle(done ? Theme.ink.opacity(0.4) : Theme.ink)
                    .strikethrough(done, color: Theme.ink.opacity(0.5))
                    .lineLimit(2)
                if let comp = habit.completion(on: date) {
                    Text("Logged \(comp.loggedAt.formatted(date: .omitted, time: .shortened))")
                        .font(Font2.sans(11, .semibold)).foregroundStyle(Theme.ink.opacity(0.4))
                }
            }

            Spacer(minLength: 8)

            Button { Haptics.tap(); HabitActions.toggle(habit, on: date, context: context); onAction() } label: {
                ZStack {
                    Circle().fill(done ? Theme.ink : Color.clear).frame(width: 28, height: 28)
                    Circle().stroke(done ? Theme.ink : Theme.ring, lineWidth: 2).frame(width: 28, height: 28)
                    if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white) }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
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

// MARK: - Day celebration — sticky note + poppers + dustbin on a blurred screen (tap to dismiss)

/// Hoisted to RootView so the celebration can blur and cover the whole screen (incl. the tab bar).
@Observable final class CelebrationCenter {
    var day: Int? = nil
}

struct DayCelebration: View {
    var day: Int
    var onDone: () -> Void
    @State private var show = false

    var body: some View {
        ZStack {
            // No solid background — the screen behind is blurred by the parent.
            ConfettiBurst().allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                note
                    .scaleEffect(show ? 1 : 0.5)
                    .opacity(show ? 1 : 0)
                Spacer()
                Image(systemName: "trash.fill")
                    .font(.system(size: 80, weight: .regular))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.bottom, 56)
                    .opacity(show ? 1 : 0)
            }
            Text("Tap to dismiss")
                .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink.opacity(0.4))
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 18)
                .opacity(show ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .onAppear {
            Haptics.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { show = true }
        }
    }

    // The same sage sticky note as the tasks, with the day number (serif italic).
    private var note: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.sage.gradient)
                .frame(width: 188, height: 188)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 14)
            Text("\(day)")
                .font(Font2.serif(112, .medium)).italic()
                .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Confetti / celebratory poppers

struct ConfettiBurst: View {
    private let colors: [Color] = [Theme.coral, Theme.periwinkle, Theme.sage, Theme.orchid, Theme.taupe]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<90, id: \.self) { i in
                    ConfettiPiece(seed: i, color: colors[i % colors.count], area: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ConfettiPiece: View {
    let seed: Int
    let color: Color
    let area: CGSize
    @State private var t: CGFloat = 0

    // deterministic pseudo-random so pieces don't reshuffle on every render
    private func rnd(_ salt: Int) -> CGFloat {
        let x = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(x - x.rounded(.down))
    }

    var body: some View {
        let startX = rnd(1) * area.width
        let drift = (rnd(2) - 0.5) * 160
        let w = 7 + rnd(3) * 7
        let h = 10 + rnd(4) * 9
        let spin = 360.0 * Double(1 + rnd(5) * 3)
        let delay = Double(rnd(6)) * 0.5
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(Double(t) * spin))
            .position(x: startX + drift * t, y: -40 + t * (area.height + 120))
            .opacity(t > 0.9 ? max(0, (1 - t) / 0.1) : 1)
            .onAppear { withAnimation(.easeIn(duration: 2.6).delay(delay)) { t = 1 } }
    }
}

// MARK: - Shared minimal header (avatar + day badge + optional trailing button)

struct TabHeader<Trailing: View>: View {
    let day: Int
    var showAvatar = true
    @ViewBuilder var trailing: () -> Trailing
    @AppStorage("profilePhotoV") private var photoVersion = 0

    var body: some View {
        HStack(alignment: .top) {
            if showAvatar {
                ZStack(alignment: .bottom) {
                    avatar
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
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }

    private var avatar: some View {
        ZStack {
            if let img = ProfilePhoto.load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.roseGradient
                Image(systemName: "person.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 66, height: 66).clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .id(photoVersion)
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
                VStack(alignment: .leading, spacing: 16) {
                    photoStrip
                    Button { addTask() } label: {
                        Text("Create Daily Task +").font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(challenge.habitsOrdered.enumerated()), id: \.element.id) { i, h in
                            taskRow(i, h)
                            if i < challenge.habitsOrdered.count - 1 { Divider().padding(.leading, 62) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }
            .her75Background()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(challenge.track.title).font(Font2.serif(20, .semibold)).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { EditHabitSheet(habit: $0, canDelete: challenge.habitsOrdered.count > 1) }
        }
    }

    // Same sticky-note row as the onboarding challenge detail.
    private func taskRow(_ i: Int, _ h: Habit) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(h.color.gradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.20), radius: 5, x: 0, y: 4)
                Text("\(i + 1)").font(Font2.serif(22, .medium)).italic().foregroundStyle(Theme.ink.opacity(0.8))
            }
            Text(h.title).font(Font2.sans(15, .bold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { editing = h } label: {
                Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink.opacity(0.55))
                    .frame(width: 30, height: 30).background(Theme.chipFill, in: Circle())
            }
        }
        .padding(.vertical, 8)
    }

    private var photoStrip: some View {
        HStack(spacing: 3) {
            ForEach(Array(challenge.track.photos.enumerated()), id: \.offset) { _, p in
                PhotoFill(name: p, fallback: HabitColor.blush.gradient)
                    .frame(maxWidth: .infinity).frame(height: 118).clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func addTask() {
        let h = Habit(title: "New daily task", subtitle: "", color: .sage, icon: "plus", order: challenge.habits.count)
        h.challenge = challenge
        context.insert(h)
        try? context.save()
        editing = h
    }
}

// Edit a single live habit (sticky note + color swatches + delete/save) — mirrors onboarding's EditTaskSheet.
struct EditHabitSheet: View {
    let habit: Habit
    var canDelete: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text("Edit task").font(Font2.serif(24, .semibold)).foregroundStyle(Theme.ink).padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                TextField("New daily task", text: bind(\.title))
                    .font(Font2.sans(18, .bold)).foregroundStyle(Theme.ink)
                TextField("Add a note", text: bind(\.subtitle))
                    .font(Font2.sans(14, .medium)).foregroundStyle(Theme.ink.opacity(0.7))
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(habit.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 12) {
                ForEach(HabitColor.palette) { c in
                    Circle().fill(c.gradient).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: habit.color == c ? 2.5 : 0))
                        .onTapGesture { Haptics.select(); habit.colorRaw = c.rawValue; try? context.save() }
                }
            }

            HStack(spacing: 12) {
                if canDelete {
                    Button { context.delete(habit); try? context.save(); dismiss() } label: {
                        Text("Delete").font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Theme.chipFill, in: Capsule())
                    }
                }
                Button { try? context.save(); dismiss() } label: {
                    Text("Save").font(Font2.sans(16, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.ink, in: Capsule())
                }
            }
            Spacer()
        }
        .padding(24)
        .presentationDetents([.height(380)])
        .her75Background()
    }

    private func bind(_ key: ReferenceWritableKeyPath<Habit, String>) -> Binding<String> {
        Binding(get: { habit[keyPath: key] }, set: { habit[keyPath: key] = $0; try? context.save() })
    }
}

