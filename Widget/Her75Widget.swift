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

// MARK: - View

struct Her75WidgetView: View {
    var entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.rose).frame(width: 14, height: 14)
                Text("Day \(entry.day) · \(entry.track)")
                    .font(Font2.sans(12, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }

            if entry.missions.isEmpty {
                Spacer()
                Text("Start your challenge in the app")
                    .font(Font2.sans(12, .medium)).foregroundStyle(Theme.ink.opacity(0.5))
                Spacer()
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
        .containerBackground(Theme.cream, for: .widget)
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
        .supportedFamilies([.systemMedium])
    }
}
