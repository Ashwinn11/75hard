import Foundation
import SwiftData
import WidgetKit

// MARK: - Challenge progress helpers

extension Challenge {

    /// Fraction of today's missions completed (0…1).
    func todayProgress() -> Double {
        let habits = habitsOrdered
        guard !habits.isEmpty else { return 0 }
        let done = habits.filter(\.isDoneToday).count
        return Double(done) / Double(habits.count)
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

    /// Toggle a habit's completion on an arbitrary day (used by the Today day-slider).
    static func toggle(_ habit: Habit, on date: Date, context: ModelContext) {
        let cal = Calendar.current
        if let existing = habit.completion(on: date) {
            if let name = existing.photoFilename {
                try? FileManager.default.removeItem(at: AppGroup.photosURL.appendingPathComponent(name))
            }
            context.delete(existing)
        } else {
            let when = cal.isDateInToday(date) ? Date() : cal.startOfDay(for: date)
            let c = Completion(loggedAt: when, dayIndex: habit.challenge?.dayIndex(of: date) ?? 1)
            c.habit = habit
            context.insert(c)
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Delete every proof-photo file a challenge's completions reference. Call BEFORE deleting the
    /// challenge or its habits: the cascade removes the Completion records but not their files,
    /// which would otherwise pile up invisibly in the shared container.
    static func deleteProofPhotos(of challenge: Challenge) {
        for habit in challenge.habits {
            for completion in habit.completions {
                if let name = completion.photoFilename {
                    try? FileManager.default.removeItem(at: AppGroup.photosURL.appendingPathComponent(name))
                }
            }
        }
    }

    /// Attach a proof photo to a habit's completion on a date (creating the completion if needed).
    static func setPhoto(_ habit: Habit, on date: Date, photo: Data, context: ModelContext) {
        let cal = Calendar.current
        let completion: Completion
        if let existing = habit.completion(on: date) {
            completion = existing
            if let old = existing.photoFilename {
                try? FileManager.default.removeItem(at: AppGroup.photosURL.appendingPathComponent(old))
            }
        } else {
            let when = cal.isDateInToday(date) ? Date() : cal.startOfDay(for: date)
            completion = Completion(loggedAt: when, dayIndex: habit.challenge?.dayIndex(of: date) ?? 1)
            completion.habit = habit
            context.insert(completion)
        }
        let name = "\(UUID().uuidString).jpg"
        try? photo.write(to: AppGroup.photosURL.appendingPathComponent(name))
        completion.photoFilename = name
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// No demo seeding: the app's data comes only from the user's onboarding choices.
// (Onboarding's finish() inserts the real Challenge + Habits.)
