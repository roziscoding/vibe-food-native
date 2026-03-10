import Foundation
import SwiftData

protocol IngredientRepository {
    func fetchActiveIngredients() throws -> [IngredientRecord]
    func insert(_ ingredient: IngredientRecord) throws
    func save() throws
    func softDelete(_ ingredient: IngredientRecord) throws
}

protocol MealRepository {
    func fetchMeals(localDayKey: String) throws -> [MealRecord]
    func insert(_ meal: MealRecord) throws
    func save() throws
    func softDelete(_ meal: MealRecord) throws
}

protocol WaterRepository {
    func fetchEntries(localDayKey: String) throws -> [WaterEntryRecord]
    func insert(_ entry: WaterEntryRecord) throws
    func save() throws
    func softDelete(_ entry: WaterEntryRecord) throws
}

protocol SettingsRepository {
    func fetchSettings() throws -> SettingsRecord?
    func insert(_ settings: SettingsRecord) throws
    func save() throws
}

protocol AIIntegrationRepository {
    func fetchIntegration() throws -> AIIntegrationRecord?
    func insert(_ integration: AIIntegrationRecord) throws
    func save() throws
}

protocol InsightRepository {
    func fetchInsight(targetLocalDayKey: String) throws -> InsightRecord?
    func hasAnyInsights() throws -> Bool
    func insert(_ insight: InsightRecord) throws
    func save() throws
}

protocol TodaySoFarRepository {
    func fetchTodaySoFar(localDayKey: String) throws -> TodaySoFarRecord?
    func insert(_ todaySoFar: TodaySoFarRecord) throws
    func save() throws
    func softDelete(_ todaySoFar: TodaySoFarRecord) throws
}

@MainActor
final class SwiftDataIngredientRepository: IngredientRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchActiveIngredients() throws -> [IngredientRecord] {
        let descriptor = FetchDescriptor<IngredientRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\IngredientRecord.name)]
        )
        return try context.fetch(descriptor)
    }

    func insert(_ ingredient: IngredientRecord) throws {
        context.insert(ingredient)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func softDelete(_ ingredient: IngredientRecord) throws {
        ingredient.deletedAt = Date()
        try save()
    }
}

@MainActor
final class SwiftDataMealRepository: MealRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchMeals(localDayKey: String) throws -> [MealRecord] {
        let descriptor = FetchDescriptor<MealRecord>(
            predicate: #Predicate { $0.localDayKey == localDayKey && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\MealRecord.consumedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func insert(_ meal: MealRecord) throws {
        context.insert(meal)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func softDelete(_ meal: MealRecord) throws {
        meal.deletedAt = Date()
        try save()
    }
}

@MainActor
final class SwiftDataWaterRepository: WaterRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchEntries(localDayKey: String) throws -> [WaterEntryRecord] {
        let descriptor = FetchDescriptor<WaterEntryRecord>(
            predicate: #Predicate { $0.localDayKey == localDayKey && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\WaterEntryRecord.consumedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func insert(_ entry: WaterEntryRecord) throws {
        context.insert(entry)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func softDelete(_ entry: WaterEntryRecord) throws {
        entry.deletedAt = Date()
        try save()
    }
}

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchSettings() throws -> SettingsRecord? {
        let descriptor = FetchDescriptor<SettingsRecord>(
            predicate: #Predicate { $0.id == "settings" }
        )
        return try context.fetch(descriptor).first
    }

    func insert(_ settings: SettingsRecord) throws {
        context.insert(settings)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}

@MainActor
final class SwiftDataAIIntegrationRepository: AIIntegrationRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchIntegration() throws -> AIIntegrationRecord? {
        let descriptor = FetchDescriptor<AIIntegrationRecord>(
            predicate: #Predicate { $0.id == "ai-integration" }
        )
        return try context.fetch(descriptor).first
    }

    func insert(_ integration: AIIntegrationRecord) throws {
        context.insert(integration)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}

@MainActor
final class SwiftDataInsightRepository: InsightRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchInsight(targetLocalDayKey: String) throws -> InsightRecord? {
        let descriptor = FetchDescriptor<InsightRecord>(
            predicate: #Predicate { $0.targetLocalDayKey == targetLocalDayKey && $0.deletedAt == nil }
        )
        return try context.fetch(descriptor).first
    }

    func hasAnyInsights() throws -> Bool {
        let descriptor = FetchDescriptor<InsightRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    func insert(_ insight: InsightRecord) throws {
        context.insert(insight)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}

@MainActor
final class SwiftDataTodaySoFarRepository: TodaySoFarRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchTodaySoFar(localDayKey: String) throws -> TodaySoFarRecord? {
        let descriptor = FetchDescriptor<TodaySoFarRecord>(
            predicate: #Predicate { $0.localDayKey == localDayKey && $0.deletedAt == nil }
        )
        return try context.fetch(descriptor).first
    }

    func insert(_ todaySoFar: TodaySoFarRecord) throws {
        context.insert(todaySoFar)
        try save()
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    func softDelete(_ todaySoFar: TodaySoFarRecord) throws {
        todaySoFar.deletedAt = Date()
        try save()
    }
}
