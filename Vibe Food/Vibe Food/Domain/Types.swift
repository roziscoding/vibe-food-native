import Foundation

struct MacroBreakdown: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct MacroTargets: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct IngredientDraft: Equatable, Identifiable {
    var id: UUID
    var name: String
    var unit: String
    var portionSize: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        portionSize: Double,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.portionSize = portionSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

struct MealDraftIngredientLine: Equatable, Identifiable {
    var id: UUID
    var ingredientId: UUID?
    var name: String
    var amount: Double
    var unit: String

    init(
        id: UUID = UUID(),
        ingredientId: UUID? = nil,
        name: String,
        amount: Double,
        unit: String
    ) {
        self.id = id
        self.ingredientId = ingredientId
        self.name = name
        self.amount = amount
        self.unit = unit
    }
}

struct ImportIssue: Equatable, Identifiable {
    var id: UUID
    var lineId: UUID
    var message: String
}

struct MealDraft: Equatable, Identifiable {
    var id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var consumedAt: Date
    var timeZoneIdentifier: String
    var localDayKey: String
    var ingredientLines: [MealDraftIngredientLine]
    var stagedIngredients: [IngredientDraft]
    var importIssues: [ImportIssue]

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
        ingredientLines: [MealDraftIngredientLine] = [],
        stagedIngredients: [IngredientDraft] = [],
        importIssues: [ImportIssue] = []
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
        self.ingredientLines = ingredientLines
        self.stagedIngredients = stagedIngredients
        self.importIssues = importIssues
    }
}

struct DailySummary: Equatable {
    var localDayKey: String
    var meals: [MealRecord]
    var totals: MacroBreakdown
    var goalProgress: MacroBreakdown
}

enum ValidationError: Error, Equatable {
    case invalidValue(field: String)
    case missingField(field: String)
}

enum MealEditorMode: String, Codable, CaseIterable, Identifiable {
    case create
    case edit
    case reviewImport

    var id: String { rawValue }
}

enum MealEntryMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case ingredients

    var id: String { rawValue }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary
    case lowActive
    case active
    case veryActive

    var id: String { rawValue }
}

enum GoalObjective: String, Codable, CaseIterable, Identifiable {
    case loseWeight
    case maintainWeight
    case gainWeight
    case muscle

    var id: String { rawValue }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }
}

struct WaterQuickAmountsConfig {
    static let defaultValues: [Double] = [250, 500, 750]

    static func parse(csv: String?) -> [Double] {
        guard let csv,
              !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValues
        }

        let parsed = csv
            .split(separator: ",")
            .compactMap { part -> Double? in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(trimmed) else { return nil }
                return value
            }

        return normalize(parsed)
    }

    static func serialize(_ values: [Double]) -> String {
        normalize(values)
            .map { String(Int($0.rounded())) }
            .joined(separator: ",")
    }

    static func normalize(_ values: [Double]) -> [Double] {
        var normalized: [Double] = []

        for value in values.map({ $0.rounded() }) {
            guard value > 0 else { continue }
            if normalized.contains(where: { $0 == value }) { continue }
            normalized.append(value)
        }

        if normalized.isEmpty {
            normalized = defaultValues
        }

        while normalized.count < defaultValues.count {
            normalized.append(defaultValues[normalized.count])
        }

        return Array(normalized.prefix(defaultValues.count))
    }
}

struct GoalRecommendationInput: Equatable {
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var sex: Sex
    var activityLevel: ActivityLevel
    var objective: GoalObjective
}

struct GoalRecommendationOutput: Equatable {
    var targets: MacroTargets
    var waterGoalMl: Double
}
