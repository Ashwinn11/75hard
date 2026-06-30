import Foundation
import SwiftData

/// The shared SwiftData stack. The store file lives in the App Group container so the
/// widget extension can read today's missions and write completions to the same database.
enum Persistence {
    static let shared: ModelContainer = {
        let schema = Schema([Challenge.self, Habit.self, Completion.self])
        let config = ModelConfiguration(schema: schema, url: AppGroup.storeURL)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
