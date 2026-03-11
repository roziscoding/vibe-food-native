import Foundation
import Observation

@MainActor
@Observable
final class DashboardStore {
    private let mealRepository: MealRepository
    private let waterRepository: WaterRepository
    private let settingsRepository: SettingsRepository
    private let insightRepository: InsightRepository
    private let deviceId: String
    private let summaryService = DailySummaryService()
    private var cachedMealsByDayKey: [String: [MealRecord]] = [:]
    private var cachedSummaryByDayKey: [String: DailySummary] = [:]
    private var cachedWaterByDayKey: [String: [WaterEntryRecord]] = [:]
    private var cachedInsightPreviewByDayKey: [String: InsightPreview?] = [:]
    private var currentDayKey: String?

    var meals: [MealRecord] = []
    var waterEntries: [WaterEntryRecord] = []
    var summary: DailySummary?
    var goals: MacroTargets = MacroTargets(calories: 2000, protein: 150, carbs: 250, fat: 70)
    var waterGoalMl: Double = 2000
    var waterTotalMl: Double = 0
    var showsInsights: Bool = true
    var insightPreview: InsightPreview?
    var errorMessage: String?

    init(
        mealRepository: MealRepository,
        waterRepository: WaterRepository,
        settingsRepository: SettingsRepository,
        insightRepository: InsightRepository,
        deviceId: String
    ) {
        self.mealRepository = mealRepository
        self.waterRepository = waterRepository
        self.settingsRepository = settingsRepository
        self.insightRepository = insightRepository
        self.deviceId = deviceId
    }

    func load(for dayKey: String) {
        do {
            try refreshGoals()
            currentDayKey = dayKey

            let loadedMeals: [MealRecord]
            if let cachedMeals = cachedMealsByDayKey[dayKey] {
                loadedMeals = cachedMeals
            } else {
                let fetched = try mealRepository.fetchMeals(localDayKey: dayKey)
                cachedMealsByDayKey[dayKey] = fetched
                loadedMeals = fetched
            }

            let loadedSummary: DailySummary
            if let cachedSummary = cachedSummaryByDayKey[dayKey] {
                loadedSummary = cachedSummary
            } else {
                let computed = summaryService.summary(for: loadedMeals, goals: goals)
                cachedSummaryByDayKey[dayKey] = computed
                loadedSummary = computed
            }

            let loadedWater: [WaterEntryRecord]
            if let cachedWater = cachedWaterByDayKey[dayKey] {
                loadedWater = cachedWater
            } else {
                let fetched = try waterRepository.fetchEntries(localDayKey: dayKey)
                cachedWaterByDayKey[dayKey] = fetched
                loadedWater = fetched
            }

            let loadedInsightPreview: InsightPreview?
            if let cachedInsightPreview = cachedInsightPreviewByDayKey[dayKey] {
                loadedInsightPreview = cachedInsightPreview
            } else {
                let fetched = try fetchInsightPreview(for: dayKey)
                cachedInsightPreviewByDayKey[dayKey] = fetched
                loadedInsightPreview = fetched
            }

            meals = loadedMeals
            summary = loadedSummary
            waterEntries = loadedWater
            waterTotalMl = totalWater(for: loadedWater)
            insightPreview = loadedInsightPreview
            errorMessage = nil
        } catch {
            setError("Failed to load dashboard.", operation: "Load dashboard", error: error)
        }
    }

    func reload(for dayKey: String) {
        cachedMealsByDayKey.removeAll()
        cachedSummaryByDayKey.removeAll()
        cachedWaterByDayKey.removeAll()
        cachedInsightPreviewByDayKey.removeAll()
        load(for: dayKey)
    }

    func preloadAdjacentDays(around date: Date) {
        do {
            try refreshGoals()
            for day in adjacentDates(around: date) {
                let dayKey = LocalDayKey.key(for: day, timeZone: .current)
                if cachedMealsByDayKey[dayKey] == nil || cachedSummaryByDayKey[dayKey] == nil {
                    let loadedMeals = try mealRepository.fetchMeals(localDayKey: dayKey)
                    cachedMealsByDayKey[dayKey] = loadedMeals
                    cachedSummaryByDayKey[dayKey] = summaryService.summary(for: loadedMeals, goals: goals)
                }

                if cachedWaterByDayKey[dayKey] == nil {
                    cachedWaterByDayKey[dayKey] = try waterRepository.fetchEntries(localDayKey: dayKey)
                }

                if cachedInsightPreviewByDayKey[dayKey] == nil {
                    cachedInsightPreviewByDayKey[dayKey] = try fetchInsightPreview(for: dayKey)
                }
            }
        } catch {
            // Ignore preload failures; the active day load path still handles errors explicitly.
        }
    }

    func logWater(amountMl: Double, selectedDate: Date) {
        guard amountMl > 0 else { return }

        let consumedAt = logDate(for: selectedDate)
        let dayKey = LocalDayKey.key(for: consumedAt, timeZone: .current)
        let normalizedAmount = amountMl.rounded()

        do {
            let record = WaterEntryRecord(
                amountMl: normalizedAmount,
                consumedAt: consumedAt,
                timeZoneIdentifier: TimeZone.current.identifier,
                localDayKey: dayKey,
                lastModifiedByDeviceId: deviceId
            )
            try waterRepository.insert(record)

            let existing: [WaterEntryRecord]
            if var cached = cachedWaterByDayKey[dayKey] {
                cached.insert(record, at: 0)
                cached.sort { $0.consumedAt > $1.consumedAt }
                existing = cached
            } else {
                existing = try waterRepository.fetchEntries(localDayKey: dayKey)
            }
            cachedWaterByDayKey[dayKey] = existing

            if currentDayKey == dayKey {
                waterEntries = existing
                waterTotalMl = totalWater(for: existing)
            }

            AppDataChangeNotifier.post(.water)
        } catch {
            setError("Failed to log water.", operation: "Log water from dashboard", error: error)
        }
    }

    private func refreshGoals() throws {
        if let settings = try settingsRepository.fetchSettings() {
            goals = NutritionRounding.round(
                MacroTargets(
                    calories: settings.calorieGoal,
                    protein: settings.proteinGoal,
                    carbs: settings.carbsGoal,
                    fat: settings.fatGoal
                )
            )
            waterGoalMl = settings.waterGoal ?? 2000
            showsInsights = settings.showsInsights ?? true
        } else {
            showsInsights = true
        }
    }

    private func fetchInsightPreview(for dayKey: String) throws -> InsightPreview? {
        guard let existing = try insightRepository.fetchInsight(targetLocalDayKey: dayKey) else {
            return nil
        }

        let summary: String
        if let data = existing.content.data(using: .utf8),
           let structured = try? JSONDecoder().decode(InsightContent.self, from: data) {
            summary = structured.summary
        } else {
            summary = existing.content
        }

        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty else { return nil }

        return InsightPreview(
            summary: normalizedSummary,
            providerLabel: existing.providerLabel
        )
    }

    private func totalWater(for entries: [WaterEntryRecord]) -> Double {
        entries.reduce(0) { partial, entry in
            partial + entry.amountMl
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

    private func logDate(for selectedDate: Date) -> Date {
        let now = Date()
        let selectedKey = LocalDayKey.key(for: selectedDate, timeZone: .current)
        let todayKey = LocalDayKey.key(for: now, timeZone: .current)
        guard selectedKey != todayKey else { return now }

        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        var components = DateComponents()
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? selectedDate
    }

    private func setError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.dashboardAlert,
            feature: "Dashboard",
            operation: operation,
            userMessage: message,
            error: error
        )
    }
}

struct InsightPreview {
    let summary: String
    let providerLabel: String
}
