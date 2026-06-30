import AppIntents
import SwiftData
import WidgetKit

/// Toggles today's completion for a mission straight from the widget — no app launch.
/// iOS 17+ interactive widgets run this AppIntent in-process and reload the timeline.
struct ToggleMissionIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle today's mission"

    @Parameter(title: "Habit")
    var habitID: String

    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = Persistence.shared.mainContext
        let uuid = UUID(uuidString: habitID)
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        if let habit = habits.first(where: { $0.id == uuid }) {
            HabitActions.toggleToday(habit, context: context)
        }
        return .result()
    }
}
