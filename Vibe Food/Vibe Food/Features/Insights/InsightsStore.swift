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
    private let insightsService = InsightsService()
    private let inputBuilder = InsightInputBuilder()
    private var cachedInsightsByDayKey: [String: CachedInsight] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    var insightText: String?
    var providerLabel: String?
    var sourceDayKey: String?
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var showsOnboarding: Bool = false
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
        guard !showsOnboarding else { return }

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

    func loadOrGenerate(
        for targetDate: Date,
        targetDayKey: String,
        forceRefresh: Bool = false,
        allowInitialGeneration: Bool = false
    ) async {
        loadTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoadOrGenerate(
                for: targetDate,
                targetDayKey: targetDayKey,
                forceRefresh: forceRefresh,
                allowInitialGeneration: allowInitialGeneration
            )
        }
        loadTask = task
        await task.value
    }

    private func performLoadOrGenerate(
        for targetDate: Date,
        targetDayKey: String,
        forceRefresh: Bool,
        allowInitialGeneration: Bool
    ) async {
        do {
            let hasAnyInsights = try insightRepository.hasAnyInsights()
            if !hasAnyInsights && !allowInitialGeneration {
                resetToOnboardingState()
                return
            }
            showsOnboarding = false
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                setError(description, operation: "Check insights availability", error: error)
            } else {
                setError("Failed to check insights. \(error)", operation: "Check insights availability", error: error)
            }
            return
        }

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
                setError(description, operation: "Load or generate insights", error: error)
            } else {
                setError("Failed to load insights. \(error)", operation: "Load or generate insights", error: error)
            }
        }
    }

    func showOnboardingIfNeeded() {
        do {
            if try !insightRepository.hasAnyInsights() {
                resetToOnboardingState()
            }
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                setError(description, operation: "Check onboarding insights state", error: error)
            } else {
                setError("Failed to check insights. \(error)", operation: "Check onboarding insights state", error: error)
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
        let goals = try inputBuilder.fetchGoals(settingsRepository: settingsRepository)
        let profile = try inputBuilder.fetchProfile(settingsRepository: settingsRepository)
        let input = inputBuilder.makeInput(
            targetDay: targetDayKey,
            sourceDay: previousDayKey,
            meals: previousMeals,
            goals: goals,
            profile: profile
        )

        let integration = try aiIntegrationRepository.fetchIntegration()
        let result: InsightsService.InsightResult
        do {
            result = try await insightsService.generateInsights(input: input, integration: integration)
        } catch {
            ErrorReportService.capture(
                key: ErrorReportKey.insightsStatus,
                feature: "Insights",
                operation: "Generate insights",
                userMessage: "Failed to generate insights.",
                error: error,
                llmInput: makeInsightInputLog(input: input),
                llmProvider: providerLabel(for: integration)
            )
            throw error
        }

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

    private func resetToOnboardingState() {
        loadTask?.cancel()
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        cachedInsightsByDayKey.removeAll()
        insightText = nil
        providerLabel = nil
        sourceDayKey = nil
        isLoading = false
        isRefreshing = false
        errorMessage = nil
        showsOnboarding = true
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

    private func previousDay(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    }

    private func setError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.insightsStatus,
            feature: "Insights",
            operation: operation,
            userMessage: message,
            error: error,
            llmOutput: insightText,
            llmProvider: providerLabel
        )
    }

    private func providerLabel(for integration: AIIntegrationRecord?) -> String {
        guard let integration,
              !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Local model"
        }
        return integration.provider == .openai ? "OpenAI" : "Anthropic"
    }

    private func makeInsightInputLog(input: InsightGenerationInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(input),
              let text = String(data: data, encoding: .utf8) else {
            return "Failed to encode insights input payload."
        }
        return text
    }
}
private struct CachedInsight {
    let content: String
    let providerLabel: String?
    let sourceDayKey: String?
}
