import Foundation
import SwiftData

// MARK: - Challenge track ("Choose your hard")

/// The difficulty tracks. One challenge *engine* configured differently per track, rather
/// than five hardcoded modes.
enum ChallengeTrack: String, Codable, CaseIterable, Identifiable {
    case her75, hard, medium, soft, betterMe, glowUp, sugarFree, mentalWellness, hotter, squat30, custom
    var id: String { rawValue }

    /// The catalog shown in onboarding (Custom is offered separately).
    static var catalog: [ChallengeTrack] {
        [.her75, .hard, .medium, .soft, .betterMe, .glowUp, .sugarFree, .mentalWellness, .hotter, .squat30]
    }

    var title: String {
        switch self {
        case .her75:          return "Her 75 Challenge"
        case .hard:           return "75 Day Hard"
        case .medium:         return "75 Medium"
        case .soft:           return "75 Soft"
        case .betterMe:       return "Better Me"
        case .glowUp:         return "Glow Up"
        case .sugarFree:      return "Sugar Free"
        case .mentalWellness: return "Mental Wellness"
        case .hotter:         return "75 Hotter Challenge"
        case .squat30:        return "30 Squat Challenge"
        case .custom:         return "Custom Challenge"
        }
    }

    var blurb: String {
        switch self {
        case .her75:          return "Made for women, by women"
        case .hard:           return "The original, no compromises"
        case .medium:         return "Disciplined, but realistic"
        case .soft:           return "A gentle reset"
        case .betterMe:       return "Habits that actually stick"
        case .glowUp:         return "Look and feel your best"
        case .sugarFree:      return "Kick the sugar habit"
        case .mentalWellness: return "Calm, clear, grounded"
        case .hotter:         return "Disciplined, all the way up"
        case .squat30:        return "30 days, stronger legs"
        case .custom:         return "Build your own from scratch"
        }
    }

    var joined: String {
        switch self {
        case .her75:          return "+24,872 joined"
        case .hard:           return "+9,999 joined"
        case .medium:         return "+4,999 joined"
        case .soft:           return "+7,498 joined"
        case .betterMe:       return "+1,847 joined"
        case .glowUp:         return "+1,259 joined"
        case .sugarFree:      return "+592 joined"
        case .mentalWellness: return "+537 joined"
        case .hotter:         return "+601 joined"
        case .squat30:        return "+588 joined"
        case .custom:         return ""
        }
    }

    /// 4-photo strip for the list card (falls back to gradients if the images are absent).
    var photos: [String] { (1...4).map { "ch_\(rawValue)_\($0)" } }

    var defaultDays: Int {
        switch self {
        case .squat30, .glowUp, .sugarFree, .mentalWellness: return 30
        default: return 75
        }
    }

    var restartOnMiss: Bool { self == .hard || self == .hotter }
    var streakProtection: Bool { !restartOnMiss }

    /// The challenge's daily tasks (titles only; sticky color / icon / card photo are derived).
    var defaultHabits: [HabitSeed] {
        switch self {
        case .her75:          return Self.mk(["Eat clean (no junk food and no alcohol)", "Drink only water", "Walk 10,000 steps a day", "One 45-minute workout per day", "Read 10 pages or a podcast (5+ min)", "Progress photo"])
        case .hard:           return Self.mk(["Two 45-minute workouts (one outdoors)", "Drink 1 gallon of water", "Read 10 pages of non-fiction", "Follow a strict diet — no cheat meals", "No alcohol", "Progress photo"])
        case .medium:         return Self.mk(["One 45-minute workout", "Drink 3L of water", "Read 10 pages", "Eat clean (1 exception a week)", "No alcohol", "Progress photo"])
        case .soft:           return Self.mk(["Eat clean (2 exceptions a week)", "Drink water", "Walk 10,000 steps a day", "Listen to a podcast (5+ min)", "Progress photo"])
        case .betterMe:       return Self.mk(["Move your body 20 min", "Drink water", "Read or learn 10 min", "One mindful meal", "Progress photo"])
        case .glowUp:         return Self.mk(["Skincare AM & PM", "Drink water", "Walk 10,000 steps", "Sleep 8 hours", "Eat whole foods", "Progress photo"])
        case .sugarFree:      return Self.mk(["Fruit is okay (whole, in moderation)", "Drink water", "No added sugar (check labels)", "No sweets (cookies, chocolate, pastries)", "No sugary drinks (soda, juices)", "No alcohol"])
        case .mentalWellness: return Self.mk(["Write 1 happy, 1 to improve, 1 proud of", "Take a walk", "Read 10 pages or a podcast", "Meditate or breathe (5–10 min)", "Limit social media & screens"])
        case .hotter:         return Self.mk(["Two workouts a day", "Drink 1 gallon of water", "Eat high-protein & clean", "Walk 10,000 steps", "No alcohol", "Progress photo"])
        case .squat30:        return Self.mk(["4 squats", "20 pulses", "7 squats", "4 squats (second set)", "20 pulses (second set)"])
        case .custom:         return Self.mk(["Move your body", "Drink water", "Read or learn", "Eat with intention"])
        }
    }

    // Derive a sticky color, icon, and card photo from each task's title.
    private static let stickyColors: [HabitColor] = HabitColor.palette
    private static func mk(_ titles: [String]) -> [HabitSeed] {
        titles.enumerated().map { i, t in
            HabitSeed(t, "", stickyColors[i % stickyColors.count], icon(for: t), photo(for: t))
        }
    }
    private static func icon(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("water") { return "drop.fill" }
        if t.contains("squat") || t.contains("pulse") { return "figure.strengthtraining.functional" }
        if t.contains("workout") || t.contains("move") { return "figure.run" }
        if t.contains("walk") || t.contains("step") { return "figure.walk" }
        if t.contains("read") || t.contains("podcast") || t.contains("book") { return "book.fill" }
        if t.contains("alcohol") { return "wineglass" }
        if t.contains("photo") { return "camera.fill" }
        if t.contains("skincare") { return "sparkles" }
        if t.contains("sleep") { return "moon.fill" }
        if t.contains("meditat") || t.contains("breath") { return "leaf.fill" }
        if t.contains("write") || t.contains("journal") { return "pencil" }
        if t.contains("social") || t.contains("screen") { return "iphone" }
        return "checkmark"
    }
    private static func photo(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("water") { return "card_water" }
        if t.contains("workout") || t.contains("walk") || t.contains("step") || t.contains("squat") || t.contains("pulse") || t.contains("move") { return "card_move" }
        if t.contains("read") || t.contains("podcast") || t.contains("book") { return "card_read" }
        if t.contains("alcohol") { return "card_alcohol" }
        if t.contains("photo") { return "card_photo" }
        if t.contains("eat") || t.contains("food") || t.contains("diet") || t.contains("sugar") || t.contains("fruit") || t.contains("sweet") || t.contains("meal") || t.contains("clean") || t.contains("protein") { return "card_eat" }
        return ""
    }
}

/// Lightweight description of a default habit (used for seeding).
struct HabitSeed {
    let title: String, subtitle: String, color: HabitColor, icon: String, photo: String
    init(_ title: String, _ subtitle: String, _ color: HabitColor, _ icon: String, _ photo: String) {
        self.title = title; self.subtitle = subtitle; self.color = color; self.icon = icon; self.photo = photo
    }
}

/// An editable, not-yet-saved habit — what onboarding and the shared EditTaskSheet work on
/// before (or instead of) touching a live SwiftData Habit.
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

// MARK: - SwiftData models

@Model
final class Challenge {
    var id: UUID = UUID()
    var trackRaw: String = ChallengeTrack.her75.rawValue
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

    var track: ChallengeTrack { ChallengeTrack(rawValue: trackRaw) ?? .her75 }

    /// 1-based day number of `date` within the challenge (day 1 = the start date's day).
    func dayIndex(of date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        return (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day ?? 0) + 1
    }

    /// 1-based current day, clamped to [1, lengthDays].
    var currentDay: Int { min(max(dayIndex(of: Date()), 1), lengthDays) }

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
