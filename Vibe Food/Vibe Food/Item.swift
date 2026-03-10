//
//  Item.swift
//  Vibe Food
//
//  Created by Rogério Munhoz on 01/03/26.
//

import Foundation
import SwiftData

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic

    var id: String { rawValue }
}

@Model
final class IngredientRecord {
    var id: UUID
    var name: String
    var unit: String
    var portionSize: Double
    var caloriesPerPortion: Double
    var proteinPerPortion: Double
    var carbsPerPortion: Double
    var fatPerPortion: Double
    var caloriesPerUnit: Double
    var proteinPerUnit: Double
    var carbsPerUnit: Double
    var fatPerUnit: Double
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        portionSize: Double,
        caloriesPerPortion: Double,
        proteinPerPortion: Double,
        carbsPerPortion: Double,
        fatPerPortion: Double,
        caloriesPerUnit: Double,
        proteinPerUnit: Double,
        carbsPerUnit: Double,
        fatPerUnit: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.portionSize = portionSize
        self.caloriesPerPortion = caloriesPerPortion
        self.proteinPerPortion = proteinPerPortion
        self.carbsPerPortion = carbsPerPortion
        self.fatPerPortion = fatPerPortion
        self.caloriesPerUnit = caloriesPerUnit
        self.proteinPerUnit = proteinPerUnit
        self.carbsPerUnit = carbsPerUnit
        self.fatPerUnit = fatPerUnit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
    }
}

@Model
final class MealRecord {
    var id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var consumedAt: Date
    var timeZoneIdentifier: String
    var localDayKey: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    @Relationship(deleteRule: .cascade, inverse: \MealIngredientSnapshotRecord.meal)
    var ingredientSnapshots: [MealIngredientSnapshotRecord]

    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        consumedAt: Date,
        timeZoneIdentifier: String,
        localDayKey: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1,
        ingredientSnapshots: [MealIngredientSnapshotRecord] = []
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.consumedAt = consumedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localDayKey = localDayKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
        self.ingredientSnapshots = ingredientSnapshots
    }
}

@Model
final class WaterEntryRecord {
    var id: UUID
    var amountMl: Double
    var consumedAt: Date
    var timeZoneIdentifier: String
    var localDayKey: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    init(
        id: UUID = UUID(),
        amountMl: Double,
        consumedAt: Date,
        timeZoneIdentifier: String,
        localDayKey: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.amountMl = amountMl
        self.consumedAt = consumedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localDayKey = localDayKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
    }
}

@Model
final class MealIngredientSnapshotRecord {
    var id: UUID
    var sourceIngredientID: UUID?
    var name: String
    var amount: Double
    var unit: String
    var meal: MealRecord?

    init(
        id: UUID = UUID(),
        sourceIngredientID: UUID? = nil,
        name: String,
        amount: Double,
        unit: String,
        meal: MealRecord? = nil
    ) {
        self.id = id
        self.sourceIngredientID = sourceIngredientID
        self.name = name
        self.amount = amount
        self.unit = unit
        self.meal = meal
    }
}

@Model
final class SettingsRecord {
    var id: String
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var waterGoal: Double?
    var waterQuickAmountsCsv: String?
    var showsInsights: Bool?
    var showsTodaySoFarBanner: Bool?
    var age: Int?
    var heightCm: Double?
    var weightKg: Double?
    var sex: Sex?
    var activityLevel: ActivityLevel?
    var objective: GoalObjective?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    init(
        id: String = "settings",
        calorieGoal: Double,
        proteinGoal: Double,
        carbsGoal: Double,
        fatGoal: Double,
        waterGoal: Double? = 2000,
        waterQuickAmountsCsv: String? = WaterQuickAmountsConfig.serialize(WaterQuickAmountsConfig.defaultValues),
        showsInsights: Bool? = true,
        showsTodaySoFarBanner: Bool? = true,
        age: Int? = nil,
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        sex: Sex? = nil,
        activityLevel: ActivityLevel? = nil,
        objective: GoalObjective? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.calorieGoal = calorieGoal
        self.proteinGoal = proteinGoal
        self.carbsGoal = carbsGoal
        self.fatGoal = fatGoal
        self.waterGoal = waterGoal
        self.waterQuickAmountsCsv = waterQuickAmountsCsv
        self.showsInsights = showsInsights
        self.showsTodaySoFarBanner = showsTodaySoFarBanner
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sex = sex
        self.activityLevel = activityLevel
        self.objective = objective
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
    }
}

@Model
final class AIIntegrationRecord {
    var id: String
    var provider: AIProvider
    var apiKey: String
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    init(
        id: String = "ai-integration",
        provider: AIProvider,
        apiKey: String,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.provider = provider
        self.apiKey = apiKey
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
    }
}

@Model
final class InsightRecord {
    var id: String
    var targetLocalDayKey: String
    var sourceLocalDayKey: String
    var content: String
    var providerLabel: String
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    init(
        id: String,
        targetLocalDayKey: String,
        sourceLocalDayKey: String,
        content: String,
        providerLabel: String,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.targetLocalDayKey = targetLocalDayKey
        self.sourceLocalDayKey = sourceLocalDayKey
        self.content = content
        self.providerLabel = providerLabel
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
    }
}

@Model
final class TodaySoFarRecord {
    var id: String
    var localDayKey: String
    var mealSignature: String
    var content: String
    var providerLabel: String
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedByDeviceId: String
    var syncVersion: Int

    init(
        id: String,
        localDayKey: String,
        mealSignature: String,
        content: String,
        providerLabel: String,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedByDeviceId: String,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.localDayKey = localDayKey
        self.mealSignature = mealSignature
        self.content = content
        self.providerLabel = providerLabel
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.syncVersion = syncVersion
    }
}
