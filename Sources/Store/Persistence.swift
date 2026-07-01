import Foundation
import SwiftData

/// The shared SwiftData stack. The store file lives in the App Group container so the
/// widget extension can read today's missions and write completions to the same database.
enum Persistence {
    static let shared: ModelContainer = {
        let schema = Schema([Challenge.self, Habit.self, Completion.self])
        // Keep the SwiftData store strictly local. The app carries a CloudKit entitlement for the
        // Friends feature (talked to directly via CKContainer), but SwiftData's default
        // `cloudKitDatabase: .automatic` would otherwise try to mirror this store to CloudKit and
        // fail to load. Our habit data is deliberately device-local, so disable that mirroring.
        let config = ModelConfiguration(schema: schema, url: AppGroup.storeURL, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
