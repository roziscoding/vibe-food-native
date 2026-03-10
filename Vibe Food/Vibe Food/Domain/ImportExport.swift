import Foundation

struct AppDataBackupPayload: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let ingredients: [IngredientBackupRow]
    let meals: [MealBackupRow]
    let waterEntries: [WaterEntryBackupRow]?
    let settings: SettingsBackupRow?
    let aiIntegration: AIIntegrationBackupRow?
}

struct IngredientBackupRow: Codable {
    let id: UUID
    let name: String
    let unit: String
    let portionSize: Double
    let caloriesPerPortion: Double
    let proteinPerPortion: Double
    let carbsPerPortion: Double
    let fatPerPortion: Double
    let caloriesPerUnit: Double
    let proteinPerUnit: Double
    let carbsPerUnit: Double
    let fatPerUnit: Double
    let createdAt: Date
    let updatedAt: Date
    let lastModifiedByDeviceId: String
    let syncVersion: Int
}

struct MealBackupRow: Codable {
    struct Snapshot: Codable {
        let id: UUID
        let sourceIngredientID: UUID?
        let name: String
        let amount: Double
        let unit: String
    }

    let id: UUID
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let consumedAt: Date
    let timeZoneIdentifier: String
    let localDayKey: String
    let createdAt: Date
    let updatedAt: Date
    let lastModifiedByDeviceId: String
    let syncVersion: Int
    let ingredientSnapshots: [Snapshot]
}

struct WaterEntryBackupRow: Codable {
    let id: UUID
    let amountMl: Double
    let consumedAt: Date
    let timeZoneIdentifier: String
    let localDayKey: String
    let createdAt: Date
    let updatedAt: Date
    let lastModifiedByDeviceId: String
    let syncVersion: Int
}

struct SettingsBackupRow: Codable {
    let calorieGoal: Double
    let proteinGoal: Double
    let carbsGoal: Double
    let fatGoal: Double
    let waterGoal: Double?
    let waterQuickAmountsCsv: String?
    let showsInsights: Bool?
    let showsTodaySoFarBanner: Bool?
    let age: Int?
    let heightCm: Double?
    let weightKg: Double?
    let sex: Sex?
    let activityLevel: ActivityLevel?
    let objective: GoalObjective?
    let createdAt: Date
    let updatedAt: Date
    let lastModifiedByDeviceId: String
    let syncVersion: Int
}

struct AIIntegrationBackupRow: Codable {
    let provider: AIProvider
    let apiKey: String
    let updatedAt: Date
    let lastModifiedByDeviceId: String
    let syncVersion: Int
}

struct IngredientImportPayload: Codable {
    struct MacrosPerPortion: Codable {
        let proteinG: Double
        let carbohydratesG: Double
        let totalFatG: Double

        enum CodingKeys: String, CodingKey {
            case proteinG = "protein_g"
            case carbohydratesG = "carbohydrates_g"
            case totalFatG = "total_fat_g"
        }
    }

    let productName: String
    let portionUnit: String
    let portionSize: Double
    let calories: Double
    let macrosPerPortion: MacrosPerPortion

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case portionUnit = "portion_unit"
        case portionSize = "portion_size"
        case calories
        case macrosPerPortion = "macros_per_portion"
    }
}

struct IngredientExportRow: Codable {
    let name: String
    let uuid: String
    let unit: String
}

struct IngredientImportService {
    func parse(data: Data) throws -> IngredientDraft {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(IngredientImportPayload.self, from: data)
        return IngredientDraft(
            name: payload.productName,
            unit: payload.portionUnit.lowercased(),
            portionSize: payload.portionSize,
            calories: payload.calories,
            protein: payload.macrosPerPortion.proteinG,
            carbs: payload.macrosPerPortion.carbohydratesG,
            fat: payload.macrosPerPortion.totalFatG
        )
    }
}
