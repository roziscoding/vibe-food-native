import Foundation
import Observation

@MainActor
@Observable
final class DashboardStore {
    private let mealRepository: MealRepository
    private let settingsRepository: SettingsRepository
    private let summaryService = DailySummaryService()
    private var cachedMealsByDayKey: [String: [MealRecord]] = [:]
    private var cachedSummaryByDayKey: [String: DailySummary] = [:]

    var meals: [MealRecord] = []
    var summary: DailySummary?
    var goals: MacroTargets = MacroTargets(calories: 2000, protein: 150, carbs: 250, fat: 70)
    var errorMessage: String?

    init(mealRepository: MealRepository, settingsRepository: SettingsRepository) {
        self.mealRepository = mealRepository
        self.settingsRepository = settingsRepository
    }

    func load(for dayKey: String) {
        do {
            try refreshGoals()

            if let cachedMeals = cachedMealsByDayKey[dayKey],
               let cachedSummary = cachedSummaryByDayKey[dayKey] {
                meals = cachedMeals
                summary = cachedSummary
                errorMessage = nil
                return
            }

            let loadedMeals = try mealRepository.fetchMeals(localDayKey: dayKey)
            let loadedSummary = summaryService.summary(for: loadedMeals, goals: goals)
            cachedMealsByDayKey[dayKey] = loadedMeals
            cachedSummaryByDayKey[dayKey] = loadedSummary
            meals = loadedMeals
            summary = loadedSummary
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load dashboard."
        }
    }

    func preloadAdjacentDays(around date: Date) {
        do {
            try refreshGoals()
            for day in adjacentDates(around: date) {
                let dayKey = LocalDayKey.key(for: day, timeZone: .current)
                guard cachedMealsByDayKey[dayKey] == nil || cachedSummaryByDayKey[dayKey] == nil else { continue }
                let loadedMeals = try mealRepository.fetchMeals(localDayKey: dayKey)
                cachedMealsByDayKey[dayKey] = loadedMeals
                cachedSummaryByDayKey[dayKey] = summaryService.summary(for: loadedMeals, goals: goals)
            }
        } catch {
            // Ignore preload failures; the active day load path still handles errors explicitly.
        }
    }

    private func refreshGoals() throws {
        if let settings = try settingsRepository.fetchSettings() {
            goals = MacroTargets(
                calories: settings.calorieGoal,
                protein: settings.proteinGoal,
                carbs: settings.carbsGoal,
                fat: settings.fatGoal
            )
        }
    }

    private func adjacentDates(around date: Date) -> [Date] {
        var dates: [Date] = []
        if let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            dates.append(previous)
        }
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: date), next <= Date() {
            dates.append(next)
        }
        return dates
    }
}
