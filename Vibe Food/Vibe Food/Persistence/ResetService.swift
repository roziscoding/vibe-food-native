import Foundation
import SwiftData

struct ResetService {
    let context: ModelContext

    func resetAllData(seedDefaults: () -> Void) throws {
        try deleteAll(IngredientRecord.self)
        try deleteAll(MealIngredientSnapshotRecord.self)
        try deleteAll(MealRecord.self)
        try deleteAll(WaterEntryRecord.self)
        try deleteAll(SettingsRecord.self)
        try deleteAll(AIIntegrationRecord.self)
        try deleteAll(InsightRecord.self)
        try deleteAll(TodaySoFarRecord.self)

        try context.save()
        seedDefaults()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let results = try context.fetch(descriptor)
        results.forEach { context.delete($0) }
    }
}
