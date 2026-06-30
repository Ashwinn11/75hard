import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Challenge.createdAt, order: .reverse) private var challenges: [Challenge]
    @State private var showRestart = false
    @State private var photoItem: PhotosPickerItem?
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
                        statsCard(c)
                        nameEditor(c)
                        remindersCard
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
        .alert("Restart challenge?", isPresented: $showRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) { restart() }
        } message: {
            Text("This deletes your current challenge and all its progress, and takes you back to onboarding.")
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    ProfilePhoto.save(data)
                    Haptics.success()
                }
            }
        }
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

    private func statsCard(_ c: Challenge) -> some View {
        HStack(spacing: 0) {
            stat("\(c.currentStreak)", "streak")
            divider
            stat("\(captured(c))", "captured")
            divider
            stat("\(Int((overall(c) * 100).rounded()))%", "complete")
        }
        .padding(.vertical, 18)
        .background(Theme.roseGradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.rose.opacity(0.3), radius: 16, y: 8)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(Font2.sans(26, .heavy)).foregroundStyle(.white)
            Text(label).font(Font2.sans(11, .bold)).foregroundStyle(.white.opacity(0.85))
        }.frame(maxWidth: .infinity)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 34) }

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

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: "Soft check-ins", color: Theme.ink.opacity(0.45))
            VStack(spacing: 0) {
                ForEach(Array(ReminderSlot.allCases.enumerated()), id: \.element.id) { i, slot in
                    ReminderRow(slot: slot)
                    if i < ReminderSlot.allCases.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var restartButton: some View {
        Button(role: .destructive) { showRestart = true } label: {
            Text("Restart challenge")
                .font(Font2.sans(15, .bold)).foregroundStyle(Theme.rose)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Theme.rose.opacity(0.4), lineWidth: 1.5))
        }
    }

    // MARK: data
    private func captured(_ c: Challenge) -> Int {
        let p = c.photoHabit
        return c.transformationCells(photoHabit: p).filter {
            if case .empty = $0 { return false }; if case .camera = $0 { return false }; return true
        }.count
    }
    private func overall(_ c: Challenge) -> Double {
        let habits = c.habitsOrdered
        guard !habits.isEmpty, c.currentDay > 0 else { return 0 }
        let possible = habits.count * c.currentDay
        let done = habits.reduce(0) { $0 + $1.completions.count }
        return possible == 0 ? 0 : min(1, Double(done) / Double(possible))
    }

    private func restart() {
        if let c = challenge { context.delete(c); try? context.save() }
        for slot in ReminderSlot.allCases { Reminders.cancel(slot) }
        Haptics.rigid()
    }
}

// MARK: - Reminder row

private struct ReminderRow: View {
    let slot: ReminderSlot
    @AppStorage private var on: Bool
    @AppStorage private var minutes: Int

    init(slot: ReminderSlot) {
        self.slot = slot
        _on = AppStorage(wrappedValue: false, "rem.\(slot.rawValue).on")
        let def = (slot.defaultTime.hour ?? 8) * 60 + (slot.defaultTime.minute ?? 0)
        _minutes = AppStorage(wrappedValue: def, "rem.\(slot.rawValue).min")
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                if on { Reminders.schedule(slot, at: DateComponents(hour: c.hour, minute: c.minute)) }
            })
    }

    var body: some View {
        HStack {
            Text(slot.title).font(Font2.sans(16, .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if on {
                DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
            }
            Toggle("", isOn: Binding(get: { on }, set: { newValue in
                on = newValue
                if newValue {
                    Task {
                        _ = await Reminders.requestAuth()
                        Reminders.schedule(slot, at: DateComponents(hour: minutes / 60, minute: minutes % 60))
                    }
                } else {
                    Reminders.cancel(slot)
                }
            })).labelsHidden().tint(Theme.rose)
        }
        .padding(14)
    }
}
