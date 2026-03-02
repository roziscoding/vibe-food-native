import Foundation

struct NutritionDerivationService {
    func derivePerUnit(from draft: IngredientDraft) throws -> MacroBreakdown {
        guard draft.portionSize > 0 else {
            throw ValidationError.invalidValue(field: "portionSize")
        }

        let calories = draft.calories / draft.portionSize
        let protein = draft.protein / draft.portionSize
        let carbs = draft.carbs / draft.portionSize
        let fat = draft.fat / draft.portionSize

        if [calories, protein, carbs, fat].contains(where: { !$0.isFinite || $0 < 0 }) {
            throw ValidationError.invalidValue(field: "macros")
        }

        return MacroBreakdown(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

struct DailySummaryService {
    func summary(for meals: [MealRecord], goals: MacroTargets) -> DailySummary {
        let totals = meals.reduce(MacroBreakdown(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, meal in
            MacroBreakdown(
                calories: partial.calories + meal.calories,
                protein: partial.protein + meal.protein,
                carbs: partial.carbs + meal.carbs,
                fat: partial.fat + meal.fat
            )
        }

        let progress = MacroBreakdown(
            calories: goals.calories > 0 ? totals.calories / goals.calories : 0,
            protein: goals.protein > 0 ? totals.protein / goals.protein : 0,
            carbs: goals.carbs > 0 ? totals.carbs / goals.carbs : 0,
            fat: goals.fat > 0 ? totals.fat / goals.fat : 0
        )

        let dayKey = meals.first?.localDayKey ?? ""
        return DailySummary(localDayKey: dayKey, meals: meals, totals: totals, goalProgress: progress)
    }
}

struct GoalRecommendationService {
    func recommend(from input: GoalRecommendationInput) -> GoalRecommendationOutput {
        let bmr = bmrValue(input: input)
        let maintenance = bmr * activityMultiplier(level: input.activityLevel, sex: input.sex)
        let adjustment = calorieAdjustment(for: input.objective)
        let calories = max(1200, round(maintenance + adjustment))

        let targets = macroTargets(for: input.objective, calories: calories, weightKg: input.weightKg)
        return GoalRecommendationOutput(targets: targets)
    }

    private func bmrValue(input: GoalRecommendationInput) -> Double {
        let base = (9.99 * input.weightKg) + (6.25 * input.heightCm) - (4.92 * Double(input.age))
        switch input.sex {
        case .female:
            return base - 161
        case .male:
            return base + 5
        }
    }

    private func activityMultiplier(level: ActivityLevel, sex: Sex) -> Double {
        switch (sex, level) {
        case (.male, .sedentary):
            return 1.00
        case (.male, .lowActive):
            return 1.11
        case (.male, .active):
            return 1.25
        case (.male, .veryActive):
            return 1.48
        case (.female, .sedentary):
            return 1.00
        case (.female, .lowActive):
            return 1.12
        case (.female, .active):
            return 1.27
        case (.female, .veryActive):
            return 1.45
        }
    }

    private func calorieAdjustment(for objective: GoalObjective) -> Double {
        switch objective {
        case .loseWeight:
            return -500
        case .maintainWeight:
            return 0
        case .gainWeight:
            return 300
        case .muscle:
            return 250
        }
    }

    private func macroTargets(for objective: GoalObjective, calories: Double, weightKg: Double) -> MacroTargets {
        switch objective {
        case .loseWeight:
            return MacroTargets(
                calories: calories,
                protein: max(1, round((0.30 * calories) / 4)),
                carbs: max(1, round((0.45 * calories) / 4)),
                fat: max(1, round((0.25 * calories) / 9))
            )
        case .maintainWeight:
            return MacroTargets(
                calories: calories,
                protein: max(1, round((0.20 * calories) / 4)),
                carbs: max(1, round((0.50 * calories) / 4)),
                fat: max(1, round((0.30 * calories) / 9))
            )
        case .gainWeight:
            return MacroTargets(
                calories: calories,
                protein: max(1, round((0.20 * calories) / 4)),
                carbs: max(1, round((0.55 * calories) / 4)),
                fat: max(1, round((0.25 * calories) / 9))
            )
        case .muscle:
            let fatRaw = (0.25 * calories) / 9
            let proteinBase = (0.25 * calories) / 4
            let proteinFloor = 1.6 * weightKg
            let proteinRaw = max(proteinBase, proteinFloor)
            let carbCalories = max(0, calories - (4 * proteinRaw) - (9 * fatRaw))

            return MacroTargets(
                calories: calories,
                protein: max(1, round(proteinRaw)),
                carbs: max(1, round(carbCalories / 4)),
                fat: max(1, round(fatRaw))
            )
        }
    }
}
