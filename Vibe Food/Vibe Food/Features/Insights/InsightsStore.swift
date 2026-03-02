import Foundation
import Observation

@MainActor
@Observable
final class InsightsStore {
    private let mealRepository: MealRepository
    private let settingsRepository: SettingsRepository
    private let aiIntegrationRepository: AIIntegrationRepository
    private let insightRepository: InsightRepository
    private let deviceId: String
    private let summaryService = DailySummaryService()
    private let insightsService = InsightsService()
    private var cachedInsightsByDayKey: [String: CachedInsight] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    var insightText: String?
    var providerLabel: String?
    var sourceDayKey: String?
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var errorMessage: String?
    private var loadTask: Task<Void, Never>?

    init(
        mealRepository: MealRepository,
        settingsRepository: SettingsRepository,
        aiIntegrationRepository: AIIntegrationRepository,
        insightRepository: InsightRepository,
        deviceId: String
    ) {
        self.mealRepository = mealRepository
        self.settingsRepository = settingsRepository
        self.aiIntegrationRepository = aiIntegrationRepository
        self.insightRepository = insightRepository
        self.deviceId = deviceId
    }

    func showCachedInsightIfAvailable(for targetDayKey: String) {
        if let cached = cachedInsightsByDayKey[targetDayKey] {
            apply(cached)
            errorMessage = nil
            return
        }

        if let existing = try? insightRepository.fetchInsight(targetLocalDayKey: targetDayKey) {
            let cached = CachedInsight(
                content: existing.content,
                providerLabel: existing.providerLabel,
                sourceDayKey: existing.sourceLocalDayKey
            )
            cachedInsightsByDayKey[targetDayKey] = cached
            apply(cached)
            errorMessage = nil
        }
    }

    func loadOrGenerate(for targetDate: Date, targetDayKey: String, forceRefresh: Bool = false) async {
        loadTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoadOrGenerate(for: targetDate, targetDayKey: targetDayKey, forceRefresh: forceRefresh)
        }
        loadTask = task
        await task.value
    }

    private func performLoadOrGenerate(for targetDate: Date, targetDayKey: String, forceRefresh: Bool) async {
        if !forceRefresh, let cached = cachedInsightsByDayKey[targetDayKey] {
            apply(cached)
            errorMessage = nil
            scheduleAdjacentPreload(around: targetDate, currentDayKey: targetDayKey)
            return
        }

        isLoading = true
        isRefreshing = forceRefresh
        errorMessage = nil
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            if !forceRefresh, let prefetchTask = prefetchTasks[targetDayKey] {
                await prefetchTask.value
                if let cached = cachedInsightsByDayKey[targetDayKey] {
                    apply(cached)
                    errorMessage = nil
                    scheduleAdjacentPreload(around: targetDate, currentDayKey: targetDayKey)
                    return
                }
            }

            let resolved = try await resolveInsight(for: targetDate, targetDayKey: targetDayKey, forceRefresh: forceRefresh)
            cachedInsightsByDayKey[targetDayKey] = resolved
            apply(resolved)
            scheduleAdjacentPreload(around: targetDate, currentDayKey: targetDayKey)
        } catch is CancellationError {
            errorMessage = nil
        } catch let error as URLError where error.code == .cancelled {
            errorMessage = nil
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                errorMessage = description
            } else {
                errorMessage = "Failed to load insights. \(error)"
            }
        }
    }

    private func resolveInsight(for targetDate: Date, targetDayKey: String, forceRefresh: Bool) async throws -> CachedInsight {
        let existing = try insightRepository.fetchInsight(targetLocalDayKey: targetDayKey)

        if let existing, !forceRefresh {
            return CachedInsight(
                content: existing.content,
                providerLabel: existing.providerLabel,
                sourceDayKey: existing.sourceLocalDayKey
            )
        }

        let previousDate = previousDay(from: targetDate)
        let previousDayKey = LocalDayKey.key(for: previousDate, timeZone: .current)
        let previousMeals = try mealRepository.fetchMeals(localDayKey: previousDayKey)
        let goals = try fetchGoals()
        let summary = summaryService.summary(for: previousMeals, goals: goals)
        let profile = try fetchProfile()

        let input = InsightGenerationInput(
            targetDay: targetDayKey,
            sourceDay: previousDayKey,
            profile: profile,
            goals: .init(
                calories: goals.calories,
                protein: goals.protein,
                carbs: goals.carbs,
                fat: goals.fat
            ),
            previousDayTotals: .init(
                calories: summary.totals.calories,
                protein: summary.totals.protein,
                carbs: summary.totals.carbs,
                fat: summary.totals.fat
            ),
            previousDayMeals: previousMeals.map {
                InsightGenerationInput.MealPayload(
                    name: $0.name,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    time: AppFormatters.shortTime.string(from: $0.consumedAt)
                )
            }
        )

        let integration = try aiIntegrationRepository.fetchIntegration()
        let result = try await insightsService.generateInsights(input: input, integration: integration)

        if let existing {
            existing.sourceLocalDayKey = previousDayKey
            existing.content = result.content
            existing.providerLabel = result.providerLabel
            existing.touch(updatedBy: deviceId)
            try insightRepository.save()
        } else {
            let record = InsightRecord(
                id: "insight-\(targetDayKey)",
                targetLocalDayKey: targetDayKey,
                sourceLocalDayKey: previousDayKey,
                content: result.content,
                providerLabel: result.providerLabel,
                lastModifiedByDeviceId: deviceId
            )
            try insightRepository.insert(record)
        }

        return CachedInsight(
            content: result.content,
            providerLabel: result.providerLabel,
            sourceDayKey: previousDayKey
        )
    }

    private func apply(_ cached: CachedInsight) {
        insightText = cached.content
        providerLabel = cached.providerLabel
        sourceDayKey = cached.sourceDayKey
    }

    private func scheduleAdjacentPreload(around targetDate: Date, currentDayKey: String) {
        for date in adjacentDates(around: targetDate) {
            let dayKey = LocalDayKey.key(for: date, timeZone: .current)
            guard dayKey != currentDayKey else { continue }
            guard cachedInsightsByDayKey[dayKey] == nil else { continue }
            guard prefetchTasks[dayKey] == nil else { continue }

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.prefetchTasks[dayKey] = nil }
                do {
                    let resolved = try await self.resolveInsight(for: date, targetDayKey: dayKey, forceRefresh: false)
                    self.cachedInsightsByDayKey[dayKey] = resolved
                } catch is CancellationError {
                } catch let error as URLError where error.code == .cancelled {
                } catch {
                    // Ignore background preload failures; the active day load path still handles errors explicitly.
                }
            }

            prefetchTasks[dayKey] = task
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

    private func fetchGoals() throws -> MacroTargets {
        if let settings = try settingsRepository.fetchSettings() {
            return MacroTargets(
                calories: settings.calorieGoal,
                protein: settings.proteinGoal,
                carbs: settings.carbsGoal,
                fat: settings.fatGoal
            )
        }

        return MacroTargets(calories: 2000, protein: 150, carbs: 250, fat: 70)
    }

    private func fetchProfile() throws -> InsightGenerationInput.ProfilePayload? {
        guard let settings = try settingsRepository.fetchSettings(),
              let age = settings.age,
              let heightCm = settings.heightCm,
              let weightKg = settings.weightKg,
              let sex = settings.sex,
              let activityLevel = settings.activityLevel,
              let objective = settings.objective else {
            return nil
        }

        return InsightGenerationInput.ProfilePayload(
            age: age,
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sex.rawValue,
            activityLevel: activityLevel.rawValue,
            objective: objective.rawValue
        )
    }

    private func previousDay(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    }
}
private struct CachedInsight {
    let content: String
    let providerLabel: String?
    let sourceDayKey: String?
}
