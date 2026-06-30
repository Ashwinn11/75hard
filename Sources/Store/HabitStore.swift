import Foundation
import SwiftData
import WidgetKit

// MARK: - Streak + transformation hive

extension Challenge {

    /// Consecutive fully-completed days ending today (or yesterday if today isn't done yet).
    var currentStreak: Int {
        let cal = Calendar.current
        let habits = habitsOrdered
        guard !habits.isEmpty else { return 0 }
        func allDone(on d: Date) -> Bool { habits.allSatisfy { $0.completion(on: d) != nil } }

        var day = cal.startOfDay(for: Date())
        if !allDone(on: day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while allDone(on: day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Fraction of today's missions completed (0…1).
    func todayProgress() -> Double {
        let habits = habitsOrdered
        guard !habits.isEmpty else { return 0 }
        let done = habits.filter(\.isDoneToday).count
        return Double(done) / Double(habits.count)
    }

    /// Cells for the transformation hive — one per challenge day. Filled days show the proof
    /// photo (or a logged gradient), today is a camera affordance, future/missed days are empty.
    func transformationCells(photoHabit: Habit?) -> [CombCell] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        let today = cal.startOfDay(for: Date())
        var out: [CombCell] = []
        for i in 0..<lengthDays {
            guard let date = cal.date(byAdding: .day, value: i, to: start) else { out.append(.empty); continue }
            if let comp = photoHabit?.completion(on: date) {
                out.append(comp.photoData.map(CombCell.photo) ?? .logged)
            } else if cal.isDate(date, inSameDayAs: today) {
                out.append(.camera)
            } else {
                out.append(.empty)
            }
        }
        return out
    }

    /// The habit used for the transformation hive (the "Progress photo" mission, else the first).
    var photoHabit: Habit? {
        habitsOrdered.first { $0.title.localizedCaseInsensitiveContains("photo") } ?? habitsOrdered.first
    }
}

// MARK: - Actions (shared by the app and the widget intent)

@MainActor
enum HabitActions {

    /// Toggle today's completion for a habit. Optionally attaches a proof photo.
    static func toggleToday(_ habit: Habit, photo: Data? = nil, context: ModelContext) {
        if let existing = habit.completion(on: Date()) {
            if let name = existing.photoFilename {
                try? FileManager.default.removeItem(at: AppGroup.photosURL.appendingPathComponent(name))
            }
            context.delete(existing)
        } else {
            var filename: String?
            if let photo {
                let name = "\(UUID().uuidString).jpg"
                try? photo.write(to: AppGroup.photosURL.appendingPathComponent(name))
                filename = name
            }
            let c = Completion(loggedAt: Date(),
                               dayIndex: habit.challenge?.currentDay ?? 1,
                               photoFilename: filename)
            c.habit = habit
            context.insert(c)
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// No demo seeding: the app's data comes only from the user's onboarding choices.
// (Onboarding's finish() inserts the real Challenge + Habits.)
