import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline model

struct MissionSnapshot: Identifiable {
    let id: UUID
    let title: String
    let color: HabitColor
    let done: Bool
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let day: Int
    let track: String
    let missions: [MissionSnapshot]
}

// MARK: - Provider

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, day: 12, track: "75 Her", missions: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(Self.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // Reload at the next midnight so the day counter / completion state rolls over.
        let next = Calendar.current.nextDate(after: .now,
                                             matching: DateComponents(hour: 0, minute: 0),
                                             matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [Self.load()], policy: .after(next)))
    }

    /// Read the shared SwiftData store with a local context (provider runs off the main actor).
    static func load() -> TodayEntry {
        let context = ModelContext(Persistence.shared)
        let challenges = (try? context.fetch(FetchDescriptor<Challenge>())) ?? []
        guard let c = challenges.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            return TodayEntry(date: .now, day: 0, track: "75 Her", missions: [])
        }
        let missions = c.habitsOrdered.map {
            MissionSnapshot(id: $0.id, title: $0.title, color: $0.color, done: $0.isDoneToday)
        }
        return TodayEntry(date: .now, day: c.currentDay, track: c.displayTitle, missions: missions)
    }
}

// MARK: - Views

struct Her75WidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodayEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                SmallMissionsView(entry: entry)
            } else {
                MediumMissionsView(entry: entry)
            }
        }
        .containerBackground(Theme.cream, for: .widget)
    }
}

/// Completed-of-total chip ("4/6"), pinned top-right on every family. Fills rose when the day is done.
private struct StatusPill: View {
    let done: Int
    let total: Int
    private var complete: Bool { total > 0 && done == total }

    var body: some View {
        Text("\(done)/\(total)")
            .font(Font2.sans(11, .heavy))
            .foregroundStyle(complete ? Color.white : Theme.ink.opacity(0.55))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(complete ? Theme.rose : Theme.chipFill, in: Capsule())
    }
}

/// Empty-state prompt, centered in whatever space it's given.
private struct EmptyMissions: View {
    var body: some View {
        Text("Start your challenge in the app")
            .font(Font2.sans(12, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Medium — colored mission tiles

private struct MediumMissionsView: View {
    let entry: TodayEntry
    private var done: Int { entry.missions.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.rose).frame(width: 14, height: 14)
                Text("Day \(entry.day) · \(entry.track)")
                    .font(Font2.sans(12, .bold)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !entry.missions.isEmpty {
                    StatusPill(done: done, total: entry.missions.count)
                }
            }

            if entry.missions.isEmpty {
                EmptyMissions()
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(entry.missions.prefix(4))) { m in
                        Button(intent: ToggleMissionIntent(habitID: m.id)) {
                            VStack(spacing: 6) {
                                Image(systemName: m.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .bold))
                                Text(m.title)
                                    .font(Font2.sans(11, .bold))
                                    .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                            }
                            .foregroundStyle(m.color.onColor)
                            .frame(maxWidth: .infinity).frame(height: 78)
                            .padding(6)
                            .background(m.color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .opacity(m.done ? 1 : 0.9)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
    }
}

// MARK: Small — day count + tappable task list (strikes through on tap)

private struct SmallMissionsView: View {
    let entry: TodayEntry
    private var done: Int { entry.missions.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Day \(entry.day)")
                    .font(Font2.sans(14, .heavy)).foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                if !entry.missions.isEmpty {
                    StatusPill(done: done, total: entry.missions.count)
                }
            }

            if entry.missions.isEmpty {
                EmptyMissions()
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(entry.missions.prefix(4))) { m in
                        Button(intent: ToggleMissionIntent(habitID: m.id)) {
                            HStack(spacing: 7) {
                                Image(systemName: m.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(m.done ? (m.color.stops.last ?? Theme.rose) : Theme.ink.opacity(0.28))
                                Text(m.title)
                                    .font(Font2.sans(12, .semibold))
                                    .strikethrough(m.done, color: Theme.ink.opacity(0.35))
                                    .foregroundStyle(m.done ? Theme.ink.opacity(0.4) : Theme.ink)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Widget

struct Her75TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: TodayProvider()) { entry in
            Her75WidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Missions")
        .description("Tap a mission to check it off without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
