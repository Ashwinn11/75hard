import Foundation
import SwiftData

// MARK: - Challenge track ("Choose your hard")

/// The difficulty tracks. One challenge *engine* configured differently per track, rather
/// than five hardcoded modes.
enum ChallengeTrack: String, Codable, CaseIterable, Identifiable {
    case her, strict, soft, hot, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .her:    return "75 Her"
        case .strict: return "75 Strict"
        case .soft:   return "75 Soft"
        case .hot:    return "75 Hot"
        case .custom: return "Custom"
        }
    }

    var blurb: String {
        switch self {
        case .her:    return "Made for women, by women"
        case .strict: return "The original, no compromises"
        case .soft:   return "A gentle reset, sustainable habits"
        case .hot:    return "Disciplined, all the way up"
        case .custom: return "Build your own from scratch"
        }
    }

    /// Missing a day wipes the run and restarts at day 1 (the original's brutal rule).
    var restartOnMiss: Bool {
        switch self {
        case .strict, .hot: return true
        case .her, .soft, .custom: return false
        }
    }

    /// A grace mechanic: a missed day can be recovered instead of resetting.
    var streakProtection: Bool { !restartOnMiss }

    /// Default daily missions seeded for this track.
    var defaultHabits: [HabitSeed] {
        switch self {
        case .strict, .hot:
            return [
                .init("Workout I", "45 min, indoors", .rose,  "figure.run", "card_move"),
                .init("Workout II", "45 min, outdoors", .berry, "figure.outdoor.cycle", "card_move"),
                .init("Drink water", "1 gallon", .sky, "drop.fill", "card_water"),
                .init("Read", "10 pages, non-fiction", .sand, "book.fill", "card_read"),
                .init("Clean eating", "no cheat meals", .sage, "leaf.fill", "card_eat"),
                .init("No alcohol", "stay dry", .lilac, "wineglass", "card_alcohol"),
                .init("Progress photo", "daily proof", .blush, "camera.fill", "card_photo"),
            ]
        case .soft:
            return [
                .init("Move your body", "20 min, your pace", .amber, "figure.walk", "card_move"),
                .init("Hydrate", "2 litres", .sky, "drop.fill", "card_water"),
                .init("Read or learn", "10 minutes", .sand, "book.fill", "card_read"),
                .init("Eat with intention", "one mindful meal", .sage, "leaf.fill", "card_eat"),
                .init("Progress photo", "gentle check-in", .blush, "camera.fill", "card_photo"),
            ]
        case .her, .custom:
            return [
                .init("Move your body", "45 min, your way", .amber, "figure.run", "card_move"),
                .init("Drink water", "3 litres", .sky, "drop.fill", "card_water"),
                .init("Read or learn", "10 pages", .sand, "book.fill", "card_read"),
                .init("Eat with intention", "clean & kind", .sage, "leaf.fill", "card_eat"),
                .init("No alcohol", "stay clear", .lilac, "wineglass", "card_alcohol"),
                .init("Progress photo", "daily proof", .blush, "camera.fill", "card_photo"),
            ]
        }
    }
}

/// Lightweight description of a default habit (used for seeding).
struct HabitSeed {
    let title: String, subtitle: String, color: HabitColor, icon: String, photo: String
    init(_ title: String, _ subtitle: String, _ color: HabitColor, _ icon: String, _ photo: String) {
        self.title = title; self.subtitle = subtitle; self.color = color; self.icon = icon; self.photo = photo
    }
}

// MARK: - SwiftData models

@Model
final class Challenge {
    var id: UUID = UUID()
    var trackRaw: String = ChallengeTrack.her.rawValue
    var lengthDays: Int = 75
    var startDate: Date = Date()
    var createdAt: Date = Date()
    var ownerName: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Habit.challenge)
    var habits: [Habit] = []

    init(track: ChallengeTrack, lengthDays: Int, startDate: Date, ownerName: String = "") {
        self.trackRaw = track.rawValue
        self.lengthDays = lengthDays
        self.startDate = startDate
        self.ownerName = ownerName
    }

    var track: ChallengeTrack { ChallengeTrack(rawValue: trackRaw) ?? .her }

    /// 1-based current day, clamped to [1, lengthDays].
    var currentDay: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        let today = cal.startOfDay(for: Date())
        let days = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        return min(max(days, 1), lengthDays)
    }

    var habitsOrdered: [Habit] { habits.sorted { $0.order < $1.order } }
}

@Model
final class Habit {
    var id: UUID = UUID()
    var title: String = ""
    var subtitle: String = ""
    var colorRaw: String = HabitColor.rose.rawValue
    var icon: String = "checkmark"          // SF Symbol name
    var photoName: String = ""              // bundled photo (Resources/Images), "" = none
    var order: Int = 0
    var challenge: Challenge?

    @Relationship(deleteRule: .cascade, inverse: \Completion.habit)
    var completions: [Completion] = []

    init(title: String, subtitle: String, color: HabitColor, icon: String, photoName: String = "", order: Int) {
        self.title = title; self.subtitle = subtitle
        self.colorRaw = color.rawValue; self.icon = icon; self.photoName = photoName; self.order = order
    }

    convenience init(seed: HabitSeed, order: Int) {
        self.init(title: seed.title, subtitle: seed.subtitle, color: seed.color,
                  icon: seed.icon, photoName: seed.photo, order: order)
    }

    var color: HabitColor { HabitColor(rawValue: colorRaw) ?? .rose }

    func completion(on day: Date) -> Completion? {
        let cal = Calendar.current
        return completions.first { cal.isDate($0.loggedAt, inSameDayAs: day) }
    }

    var isDoneToday: Bool { completion(on: Date()) != nil }
}

@Model
final class Completion {
    var id: UUID = UUID()
    var loggedAt: Date = Date()
    var dayIndex: Int = 1
    /// Filename (not path) of the proof photo inside `AppGroup.photosURL`. Nil = logged without a photo.
    var photoFilename: String?
    var habit: Habit?

    init(loggedAt: Date, dayIndex: Int, photoFilename: String? = nil) {
        self.loggedAt = loggedAt; self.dayIndex = dayIndex; self.photoFilename = photoFilename
    }

    /// Lazily load the proof photo bytes from the shared container.
    var photoData: Data? {
        guard let name = photoFilename else { return nil }
        return try? Data(contentsOf: AppGroup.photosURL.appendingPathComponent(name))
    }
}
