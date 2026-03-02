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
}
