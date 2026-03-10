import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MealsStore {
    private let mealRepository: MealRepository
    private let ingredientRepository: IngredientRepository
    private let todaySoFarRepository: TodaySoFarRepository
    private let settingsRepository: SettingsRepository
    private let aiIntegrationRepository: AIIntegrationRepository
    private let context: ModelContext
    private let deviceId: String
    private let importService = MealImportService()
    private let derivationService = NutritionDerivationService()
    private let aiLogService = MealAILogService()
    private let insightsService = InsightsService()
    private let insightInputBuilder = InsightInputBuilder()
    private var cachedMealsByDayKey: [String: [MealRecord]] = [:]
    private var cachedIngredients: [IngredientRecord]?
    private var cachedTodaySoFarByDayKey: [String: CachedTodaySoFar] = [:]
    private var todaySoFarTasksByDayKey: [String: Task<Void, Never>] = [:]
    private var inFlightTodaySoFarSignatures: [String: String] = [:]
    private var visibleTodaySoFarDayKey: String?

    var meals: [MealRecord] = []
    var ingredients: [IngredientRecord] = []
    var isTodaySoFarEnabled: Bool = true
    var isTodaySoFarCollapsed: Bool = false
    var todaySoFarMessage: String?
    var todaySoFarProviderLabel: String?
    var todaySoFarErrorMessage: String?
    var isLoadingTodaySoFar: Bool = false
    var draft: MealDraft?
    var entryMode: MealEntryMode = .manual
    var editingMealId: UUID?
    var isPresentingEditor: Bool = false
    var isPresentingImportSheet: Bool = false
    var isPresentingFileImporter: Bool = false
    var isPresentingAILogInput: Bool = false
    var isPresentingAILogStatus: Bool = false
    var importJSONText: String = ""
    var aiLogMealName: String = ""
    var aiLogDescription: String = ""
    var aiLogInputError: String?
    var aiLogError: String?
    var aiLogOutput: String?
    var aiLogProviderLabel: String = "Local model"
    var aiLogPhase: AILogPhase = .idle
    var shouldPresentEditorAfterAILog: Bool = false
    var draftError: String?
    var fieldErrors: [String: String] = [:]
    var pendingDelete: MealRecord?
    var errorMessage: String?

    init(
        mealRepository: MealRepository,
        ingredientRepository: IngredientRepository,
        todaySoFarRepository: TodaySoFarRepository,
        settingsRepository: SettingsRepository,
        aiIntegrationRepository: AIIntegrationRepository,
        context: ModelContext,
        deviceId: String
    ) {
        self.mealRepository = mealRepository
        self.ingredientRepository = ingredientRepository
        self.todaySoFarRepository = todaySoFarRepository
        self.settingsRepository = settingsRepository
        self.aiIntegrationRepository = aiIntegrationRepository
        self.context = context
        self.deviceId = deviceId
    }

    func load(for dayKey: String) {
        do {
            if let cachedMeals = cachedMealsByDayKey[dayKey] {
                meals = cachedMeals
            } else {
                let loadedMeals = try mealRepository.fetchMeals(localDayKey: dayKey)
                cachedMealsByDayKey[dayKey] = loadedMeals
                meals = loadedMeals
            }

            if let cachedIngredients {
                ingredients = cachedIngredients
            } else {
                let loadedIngredients = try ingredientRepository.fetchActiveIngredients()
                cachedIngredients = loadedIngredients
                ingredients = loadedIngredients
            }
            errorMessage = nil
        } catch {
            setAlertError("Failed to load meals.", operation: "Load meals", error: error)
        }
    }

    func reload(for dayKey: String) {
        cachedMealsByDayKey.removeAll()
        cachedIngredients = nil
        load(for: dayKey)
    }

    func loadPreferences() {
        do {
            let settings = try settingsRepository.fetchSettings()
            let isEnabled = settings?.showsTodaySoFarBanner ?? true
            applyTodaySoFarPreference(isEnabled)
        } catch {
            applyTodaySoFarPreference(true)
        }
    }

    func loadTodaySoFar(for dayKey: String, force: Bool = false) {
        visibleTodaySoFarDayKey = dayKey
        loadPreferences()

        guard isTodaySoFarEnabled else {
            clearVisibleTodaySoFar()
            return
        }

        let mealsForDay: [MealRecord]
        if let cachedMeals = cachedMealsByDayKey[dayKey] {
            mealsForDay = cachedMeals
        } else {
            do {
                let loadedMeals = try mealRepository.fetchMeals(localDayKey: dayKey)
                cachedMealsByDayKey[dayKey] = loadedMeals
                mealsForDay = loadedMeals
            } catch {
                clearTodaySoFar(for: dayKey)
                return
            }
        }

        showStoredTodaySoFarIfAvailable(for: dayKey, meals: mealsForDay)
        refreshStoredTodaySoFarIfNeeded(for: dayKey, meals: mealsForDay, force: force)
    }

    func refresh(for dayKey: String, around date: Date) async {
        reload(for: dayKey)
        preloadAdjacentDays(around: date)
        loadTodaySoFar(for: dayKey, force: true)
        if let task = todaySoFarTasksByDayKey[dayKey] {
            await task.value
        }
    }

    func toggleTodaySoFarCollapsed() {
        isTodaySoFarCollapsed.toggle()
    }

    func preloadAdjacentDays(around date: Date) {
        do {
            for day in adjacentDates(around: date) {
                let dayKey = LocalDayKey.key(for: day, timeZone: .current)
                guard cachedMealsByDayKey[dayKey] == nil else { continue }
                cachedMealsByDayKey[dayKey] = try mealRepository.fetchMeals(localDayKey: dayKey)
            }

            if cachedIngredients == nil {
                cachedIngredients = try ingredientRepository.fetchActiveIngredients()
            }
        } catch {
            // Ignore preload failures; the active day load path still handles errors explicitly.
        }
    }

    func beginCreate(consumedAt: Date, dayKey: String) {
        editingMealId = nil
        entryMode = .ingredients
        draft = MealDraft(
            name: "",
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            consumedAt: consumedAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            localDayKey: dayKey,
            ingredientLines: [],
            stagedIngredients: [],
            importIssues: []
        )
        isPresentingEditor = true
    }

    func beginEdit(_ meal: MealRecord) {
        editingMealId = meal.id

        if meal.ingredientSnapshots.isEmpty {
            entryMode = .manual
            draft = MealDraft(
                id: meal.id,
                name: meal.name,
                calories: meal.calories,
                protein: meal.protein,
                carbs: meal.carbs,
                fat: meal.fat,
                consumedAt: meal.consumedAt,
                timeZoneIdentifier: meal.timeZoneIdentifier,
                localDayKey: meal.localDayKey,
                ingredientLines: [],
                stagedIngredients: [],
                importIssues: []
            )
        } else {
            entryMode = .ingredients
            let lines = meal.ingredientSnapshots.map {
                MealDraftIngredientLine(
                    ingredientId: $0.sourceIngredientID,
                    name: $0.name,
                    amount: $0.amount,
                    unit: $0.unit
                )
            }
            draft = MealDraft(
                id: meal.id,
                name: meal.name,
                calories: meal.calories,
                protein: meal.protein,
                carbs: meal.carbs,
                fat: meal.fat,
                consumedAt: meal.consumedAt,
                timeZoneIdentifier: meal.timeZoneIdentifier,
                localDayKey: meal.localDayKey,
                ingredientLines: lines,
                stagedIngredients: [],
                importIssues: []
            )
        }

        isPresentingEditor = true
    }

    func cancelEdit() {
        isPresentingEditor = false
        draft = nil
        editingMealId = nil
        draftError = nil
        fieldErrors = [:]
    }

    func beginImportPaste() {
        importJSONText = ""
        isPresentingImportSheet = true
    }

    func beginImportFile() {
        isPresentingFileImporter = true
    }

    func beginAILog() {
        aiLogMealName = ""
        aiLogDescription = ""
        aiLogInputError = nil
        aiLogError = nil
        aiLogOutput = nil
        isPresentingAILogInput = true
    }

    func submitAILog(consumedAt: Date, dayKey: String) async {
        let trimmedDescription = aiLogDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            aiLogInputError = "Add a description before logging."
            return
        }

        aiLogInputError = nil
        aiLogError = nil
        aiLogOutput = nil
        aiLogPhase = .processing
        isPresentingAILogInput = false
        isPresentingAILogStatus = true

        let availableIngredients = ingredients.map { ingredient in
            AvailableIngredient(
                ingredientId: ingredient.id.uuidString,
                name: ingredient.name,
                unit: ingredient.unit,
                kcalPerUnit: ingredient.caloriesPerUnit,
                proteinPerUnitG: ingredient.proteinPerUnit,
                carbsPerUnitG: ingredient.carbsPerUnit,
                fatPerUnitG: ingredient.fatPerUnit
            )
        }
        let aiLogInput = makeAILogInput(
            mealName: aiLogMealName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: trimmedDescription,
            availableIngredients: availableIngredients
        )

        do {
            let integration = try? aiIntegrationRepository.fetchIntegration()
            if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiLogProviderLabel = integration.provider == .openai ? "OpenAI" : "Anthropic"
            } else {
                aiLogProviderLabel = "Local model"
            }

            let result = try await aiLogService.logMeal(
                mealName: aiLogMealName.trimmingCharacters(in: .whitespacesAndNewlines),
                description: trimmedDescription,
                availableIngredients: availableIngredients,
                integration: integration
            )

            aiLogOutput = result.rawText
            entryMode = .ingredients

            let (lines, issues) = resolveMatchedIngredientsAI(result.payload.matchedIngredients)
            let staged = result.payload.newIngredients.map {
                IngredientDraft(
                    name: $0.name,
                    unit: $0.unit.lowercased(),
                    portionSize: $0.portionSize,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat
                )
            }

            draft = MealDraft(
                name: result.payload.mealName,
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                consumedAt: consumedAt,
                timeZoneIdentifier: TimeZone.current.identifier,
                localDayKey: dayKey,
                ingredientLines: lines,
                stagedIngredients: staged,
                importIssues: issues
            )
            aiLogPhase = .success
            shouldPresentEditorAfterAILog = true
            dismissAILogStatus()
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                aiLogError = description
            } else {
                aiLogError = "Failed to log meal. \(error)"
            }
            aiLogPhase = .failure
            ErrorReportService.capture(
                key: ErrorReportKey.mealsAILog,
                feature: "Meals",
                operation: "AI meal logging",
                userMessage: aiLogError ?? "AI meal logging failed.",
                error: error,
                llmInput: aiLogInput,
                llmOutput: aiLogOutput,
                llmProvider: aiLogProviderLabel
            )
        }
    }

    func dismissAILogStatus() {
        isPresentingAILogStatus = false
        if aiLogPhase == .success, shouldPresentEditorAfterAILog {
            isPresentingEditor = true
        }
        shouldPresentEditorAfterAILog = false
        if aiLogPhase != .processing {
            aiLogPhase = .idle
        }
    }

    func importFromJSONText() {
        let trimmed = importJSONText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            setAlertError("Paste valid JSON to import.", operation: "Import meal JSON text")
            return
        }
        importFromData(data)
    }

    func importFromData(_ data: Data) {
        do {
            let payload = try importService.parse(data: data)
            let (lines, issues) = resolveMatchedIngredients(payload.matchedIngredients)
            let staged = payload.newIngredients.map {
                IngredientDraft(
                    name: $0.name,
                    unit: $0.unit.lowercased(),
                    portionSize: $0.portionSize,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat
                )
            }

            entryMode = .ingredients
            draft = MealDraft(
                name: "Imported Meal",
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                consumedAt: Date(),
                timeZoneIdentifier: TimeZone.current.identifier,
                localDayKey: LocalDayKey.key(for: Date(), timeZone: .current),
                ingredientLines: lines,
                stagedIngredients: staged,
                importIssues: issues
            )
            isPresentingImportSheet = false
            isPresentingEditor = true
        } catch {
            setAlertError("Failed to parse meal JSON.", operation: "Parse meal JSON import", error: error)
        }
    }

    func addIngredientLine() {
        guard var draft else { return }
        draft.ingredientLines.append(
            MealDraftIngredientLine(name: "", amount: 0, unit: "")
        )
        self.draft = draft
    }

    func setIngredient(lineId: UUID, ingredientId: UUID?) {
        guard var draft else { return }
        guard let index = draft.ingredientLines.firstIndex(where: { $0.id == lineId }) else { return }
        draft.ingredientLines[index].ingredientId = ingredientId
        if let ingredientId, let ingredient = ingredients.first(where: { $0.id == ingredientId }) {
            draft.ingredientLines[index].name = ingredient.name
            draft.ingredientLines[index].unit = ingredient.unit
        }
        self.draft = draft
    }

    func saveDraft() {
        guard var draft else { return }
        let hadStagedIngredients = !draft.stagedIngredients.isEmpty
        let previousDayKey = editingMealId.flatMap { editingId in
            meals.first(where: { $0.id == editingId })?.localDayKey
        }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        fieldErrors = [:]
        guard !trimmedName.isEmpty else {
            fieldErrors["name"] = "Meal name is required."
            return
        }
        draft.name = trimmedName
        draft.timeZoneIdentifier = TimeZone.current.identifier
        draft.localDayKey = LocalDayKey.key(for: draft.consumedAt, timeZone: .current)

        do {
            if !draft.stagedIngredients.isEmpty {
                let insertedIngredients = try commitStagedIngredients(from: draft)
                let refreshedIngredients = try ingredientRepository.fetchActiveIngredients()
                cachedIngredients = refreshedIngredients
                ingredients = refreshedIngredients
                draft.ingredientLines.append(contentsOf: mealLines(for: insertedIngredients))
                draft.stagedIngredients = []
            }

            if entryMode == .ingredients {
                let validLines = draft.ingredientLines.filter { line in
                    line.ingredientId != nil && line.amount > 0
                }
                guard !validLines.isEmpty else {
                    fieldErrors["ingredients"] = "Add at least one ingredient line."
                    return
                }

                let totals = computeTotals(from: validLines)
                draft.calories = totals.calories
                draft.protein = totals.protein
                draft.carbs = totals.carbs
                draft.fat = totals.fat

                let snapshots = validLines.compactMap { line -> MealIngredientSnapshotRecord? in
                    guard let ingredientId = line.ingredientId,
                          let ingredient = ingredients.first(where: { $0.id == ingredientId })
                    else { return nil }
                    return MealIngredientSnapshotRecord(
                        sourceIngredientID: ingredient.id,
                        name: ingredient.name,
                        amount: line.amount,
                        unit: ingredient.unit
                    )
                }

                try upsertMeal(with: draft, snapshots: snapshots)
            } else {
                try upsertMeal(with: draft, snapshots: [])
            }

            cachedMealsByDayKey.removeAll()
            load(for: draft.localDayKey)
            cancelEdit()
            AppDataChangeNotifier.post(.meals)
            if hadStagedIngredients {
                AppDataChangeNotifier.post(.ingredients)
            }
            refreshStoredTodaySoFarForAffectedDays(previousDayKey: previousDayKey, newDayKey: draft.localDayKey)
        } catch {
            setDraftError("Failed to save meal.", operation: "Save meal draft", error: error)
        }
    }

    func confirmDelete(_ meal: MealRecord) {
        pendingDelete = meal
    }

    func deletePending() {
        guard let meal = pendingDelete else { return }
        delete(meal)
        pendingDelete = nil
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    func delete(_ meal: MealRecord) {
        do {
            try mealRepository.softDelete(meal)
            cachedMealsByDayKey.removeAll()
            load(for: meal.localDayKey)
            AppDataChangeNotifier.post(.meals)
            refreshStoredTodaySoFarForAffectedDays(previousDayKey: meal.localDayKey)
        } catch {
            setAlertError("Failed to delete meal.", operation: "Delete meal", error: error)
        }
    }

    private func refreshStoredTodaySoFarForAffectedDays(previousDayKey: String?, newDayKey: String? = nil) {
        let affectedDayKeys = Set([previousDayKey, newDayKey].compactMap { $0 })
        guard !affectedDayKeys.isEmpty else { return }

        for dayKey in affectedDayKeys {
            let mealsForDay: [MealRecord]
            if dayKey == visibleTodaySoFarDayKey {
                mealsForDay = meals
            } else if let cachedMeals = cachedMealsByDayKey[dayKey] {
                mealsForDay = cachedMeals
            } else if let loadedMeals = try? mealRepository.fetchMeals(localDayKey: dayKey) {
                cachedMealsByDayKey[dayKey] = loadedMeals
                mealsForDay = loadedMeals
            } else {
                continue
            }

            refreshStoredTodaySoFarIfNeeded(for: dayKey, meals: mealsForDay, force: true)
        }
    }

    private func refreshStoredTodaySoFarIfNeeded(for dayKey: String, meals: [MealRecord], force: Bool) {
        guard isTodaySoFarEnabled else { return }
        let signature = todaySoFarSignature(for: meals)
        let cached = cachedTodaySoFar(for: dayKey)

        if let cached, cached.mealSignature == signature, !force {
            if visibleTodaySoFarDayKey == dayKey {
                apply(cached, for: dayKey)
            }
            return
        }

        if meals.isEmpty {
            clearPersistedTodaySoFar(for: dayKey)
            return
        }

        if !force, inFlightTodaySoFarSignatures[dayKey] == signature {
            if visibleTodaySoFarDayKey == dayKey {
                isLoadingTodaySoFar = true
            }
            return
        }

        scheduleTodaySoFarRefresh(for: dayKey, meals: meals, signature: signature)
    }

    private func scheduleTodaySoFarRefresh(for dayKey: String, meals: [MealRecord], signature: String) {
        todaySoFarTasksByDayKey[dayKey]?.cancel()
        inFlightTodaySoFarSignatures[dayKey] = signature

        if visibleTodaySoFarDayKey == dayKey {
            isLoadingTodaySoFar = true
            todaySoFarErrorMessage = nil
        }

        todaySoFarTasksByDayKey[dayKey] = Task { @MainActor [weak self] in
            guard let self else { return }
            var inputLog = ""
            defer {
                self.todaySoFarTasksByDayKey[dayKey] = nil
                self.inFlightTodaySoFarSignatures[dayKey] = nil
                if self.visibleTodaySoFarDayKey == dayKey {
                    self.isLoadingTodaySoFar = false
                }
            }

            do {
                let goals = try self.insightInputBuilder.fetchGoals(settingsRepository: self.settingsRepository)
                let profile = try self.insightInputBuilder.fetchProfile(settingsRepository: self.settingsRepository)
                let input = self.insightInputBuilder.makeInput(
                    targetDay: dayKey,
                    sourceDay: dayKey,
                    meals: meals,
                    goals: goals,
                    profile: profile
                )
                inputLog = self.makeTodaySoFarInputLog(input: input)
                let integration = try self.aiIntegrationRepository.fetchIntegration()
                let result = try await self.insightsService.generateTodaySoFarMessage(
                    input: input,
                    integration: integration
                )

                let existing = try self.todaySoFarRepository.fetchTodaySoFar(localDayKey: dayKey)
                if let existing {
                    existing.mealSignature = signature
                    existing.content = result.content
                    existing.providerLabel = result.providerLabel
                    existing.deletedAt = nil
                    existing.touch(updatedBy: self.deviceId)
                    try self.todaySoFarRepository.save()
                } else {
                    let record = TodaySoFarRecord(
                        id: "today-so-far-\(dayKey)",
                        localDayKey: dayKey,
                        mealSignature: signature,
                        content: result.content,
                        providerLabel: result.providerLabel,
                        lastModifiedByDeviceId: self.deviceId
                    )
                    try self.todaySoFarRepository.insert(record)
                }

                let cached = CachedTodaySoFar(
                    content: result.content,
                    providerLabel: result.providerLabel,
                    mealSignature: signature
                )
                self.cachedTodaySoFarByDayKey[dayKey] = cached

                if self.visibleTodaySoFarDayKey == dayKey {
                    self.apply(cached, for: dayKey)
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                if self.visibleTodaySoFarDayKey == dayKey {
                    self.todaySoFarErrorMessage = self.todaySoFarDescription(for: error)
                }
                ErrorReportService.capture(
                    key: ErrorReportKey.mealsTodaySoFar,
                    feature: "Meals",
                    operation: "Generate day summary message",
                    userMessage: self.todaySoFarErrorMessage ?? "Day summary generation failed.",
                    error: error,
                    llmInput: inputLog,
                    llmOutput: self.todaySoFarMessage,
                    llmProvider: self.todaySoFarProviderLabel
                )
            }
        }
    }

    private func showStoredTodaySoFarIfAvailable(for dayKey: String, meals: [MealRecord]) {
        let signature = todaySoFarSignature(for: meals)
        if let cached = cachedTodaySoFar(for: dayKey), cached.mealSignature == signature {
            apply(cached, for: dayKey)
            return
        }

        clearTodaySoFar(for: dayKey)
    }

    private func cachedTodaySoFar(for dayKey: String) -> CachedTodaySoFar? {
        if let cached = cachedTodaySoFarByDayKey[dayKey] {
            return cached
        }

        guard let existing = try? todaySoFarRepository.fetchTodaySoFar(localDayKey: dayKey) else {
            return nil
        }

        let cached = CachedTodaySoFar(
            content: existing.content,
            providerLabel: existing.providerLabel,
            mealSignature: existing.mealSignature
        )
        cachedTodaySoFarByDayKey[dayKey] = cached
        return cached
    }

    private func clearPersistedTodaySoFar(for dayKey: String) {
        cachedTodaySoFarByDayKey.removeValue(forKey: dayKey)
        todaySoFarTasksByDayKey[dayKey]?.cancel()
        todaySoFarTasksByDayKey[dayKey] = nil
        inFlightTodaySoFarSignatures[dayKey] = nil

        if let existing = try? todaySoFarRepository.fetchTodaySoFar(localDayKey: dayKey) {
            try? todaySoFarRepository.softDelete(existing)
        }

        if visibleTodaySoFarDayKey == dayKey {
            clearTodaySoFar(for: dayKey)
        }
    }

    private func applyTodaySoFarPreference(_ isEnabled: Bool) {
        isTodaySoFarEnabled = isEnabled

        guard !isEnabled else { return }

        todaySoFarTasksByDayKey.values.forEach { $0.cancel() }
        todaySoFarTasksByDayKey.removeAll()
        inFlightTodaySoFarSignatures.removeAll()
        clearVisibleTodaySoFar()
    }

    private func apply(_ cached: CachedTodaySoFar, for dayKey: String) {
        guard visibleTodaySoFarDayKey == dayKey else { return }
        todaySoFarMessage = cached.content
        todaySoFarProviderLabel = cached.providerLabel
        todaySoFarErrorMessage = nil
    }

    private func clearVisibleTodaySoFar() {
        todaySoFarMessage = nil
        todaySoFarProviderLabel = nil
        todaySoFarErrorMessage = nil
        isLoadingTodaySoFar = false
    }

    private func clearTodaySoFar(for dayKey: String) {
        guard visibleTodaySoFarDayKey == dayKey else { return }
        clearVisibleTodaySoFar()
    }

    private func todaySoFarDescription(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return "Failed to refresh the day summary. \(error)"
    }

    private func todaySoFarSignature(for meals: [MealRecord]) -> String {
        meals.map {
            "\($0.id.uuidString)|\($0.updatedAt.timeIntervalSince1970)|\($0.localDayKey)"
        }
        .joined(separator: ";")
    }

    private func upsertMeal(with draft: MealDraft, snapshots: [MealIngredientSnapshotRecord]) throws {
        if let editingId = editingMealId,
           let existing = meals.first(where: { $0.id == editingId }) {
            existing.name = draft.name
            existing.calories = draft.calories
            existing.protein = draft.protein
            existing.carbs = draft.carbs
            existing.fat = draft.fat
            existing.consumedAt = draft.consumedAt
            existing.timeZoneIdentifier = draft.timeZoneIdentifier
            existing.localDayKey = draft.localDayKey
            existing.touch(updatedBy: deviceId)

            existing.ingredientSnapshots.forEach { context.delete($0) }
            existing.ingredientSnapshots = snapshots

            try mealRepository.save()
        } else {
            let record = MealRecord(
                name: draft.name,
                calories: draft.calories,
                protein: draft.protein,
                carbs: draft.carbs,
                fat: draft.fat,
                consumedAt: draft.consumedAt,
                timeZoneIdentifier: draft.timeZoneIdentifier,
                localDayKey: draft.localDayKey,
                lastModifiedByDeviceId: deviceId,
                ingredientSnapshots: snapshots
            )
            try mealRepository.insert(record)
        }
    }

    private func computeTotals(from lines: [MealDraftIngredientLine]) -> MacroBreakdown {
        var totals = MacroBreakdown(calories: 0, protein: 0, carbs: 0, fat: 0)
        for line in lines {
            guard let ingredientId = line.ingredientId,
                  let ingredient = ingredients.first(where: { $0.id == ingredientId })
            else { continue }
            totals.calories += ingredient.caloriesPerUnit * line.amount
            totals.protein += ingredient.proteinPerUnit * line.amount
            totals.carbs += ingredient.carbsPerUnit * line.amount
            totals.fat += ingredient.fatPerUnit * line.amount
        }
        return totals
    }

    private func resolveMatchedIngredients(
        _ matched: [MealImportPayload.MatchedIngredient]
    ) -> ([MealDraftIngredientLine], [ImportIssue]) {
        var issues: [ImportIssue] = []
        var lines: [MealDraftIngredientLine] = []

        for match in matched {
            if let ingredient = ingredients.first(where: { $0.id == match.ingredientId }) {
                lines.append(MealDraftIngredientLine(
                    ingredientId: ingredient.id,
                    name: ingredient.name,
                    amount: match.amount,
                    unit: ingredient.unit
                ))
            } else {
                let lineId = UUID()
                lines.append(MealDraftIngredientLine(
                    id: lineId,
                    ingredientId: nil,
                    name: "Unmatched ingredient",
                    amount: match.amount,
                    unit: ""
                ))
                issues.append(ImportIssue(
                    id: UUID(),
                    lineId: lineId,
                    message: "Missing ingredient: \(match.ingredientId.uuidString)"
                ))
            }
        }

        return (lines, issues)
    }

    private func resolveMatchedIngredientsAI(
        _ matched: [MealAILogPayload.MatchedIngredient]
    ) -> ([MealDraftIngredientLine], [ImportIssue]) {
        var issues: [ImportIssue] = []
        var lines: [MealDraftIngredientLine] = []

        for match in matched {
            if let ingredient = ingredients.first(where: { $0.id == match.ingredientId }) {
                lines.append(MealDraftIngredientLine(
                    ingredientId: ingredient.id,
                    name: ingredient.name,
                    amount: match.amount,
                    unit: ingredient.unit
                ))
            } else {
                let lineId = UUID()
                lines.append(MealDraftIngredientLine(
                    id: lineId,
                    ingredientId: nil,
                    name: "Unmatched ingredient",
                    amount: match.amount,
                    unit: ""
                ))
                issues.append(ImportIssue(
                    id: UUID(),
                    lineId: lineId,
                    message: "Missing ingredient: \(match.ingredientId.uuidString)"
                ))
            }
        }

        return (lines, issues)
    }

    private func commitStagedIngredients(from draft: MealDraft) throws -> [IngredientRecord] {
        var insertedRecords: [IngredientRecord] = []
        for ingredientDraft in draft.stagedIngredients {
            let trimmedName = ingredientDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw ValidationError.missingField(field: "ingredient name")
            }
            let perUnit = try derivationService.derivePerUnit(from: ingredientDraft)
            let record = IngredientRecord(
                name: trimmedName,
                unit: ingredientDraft.unit.lowercased(),
                portionSize: ingredientDraft.portionSize,
                caloriesPerPortion: ingredientDraft.calories,
                proteinPerPortion: ingredientDraft.protein,
                carbsPerPortion: ingredientDraft.carbs,
                fatPerPortion: ingredientDraft.fat,
                caloriesPerUnit: perUnit.calories,
                proteinPerUnit: perUnit.protein,
                carbsPerUnit: perUnit.carbs,
                fatPerUnit: perUnit.fat,
                lastModifiedByDeviceId: deviceId
            )
            try ingredientRepository.insert(record)
            insertedRecords.append(record)
        }
        return insertedRecords
    }

    private func mealLines(for ingredients: [IngredientRecord]) -> [MealDraftIngredientLine] {
        ingredients.map { ingredient in
            MealDraftIngredientLine(
                ingredientId: ingredient.id,
                name: ingredient.name,
                amount: ingredient.portionSize,
                unit: ingredient.unit
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

    private func setAlertError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.mealsAlert,
            feature: "Meals",
            operation: operation,
            userMessage: message,
            error: error
        )
    }

    private func setDraftError(_ message: String, operation: String, error: Error? = nil) {
        draftError = message
        ErrorReportService.capture(
            key: ErrorReportKey.mealsDraft,
            feature: "Meals",
            operation: operation,
            userMessage: message,
            error: error
        )
    }

    private func makeAILogInput(
        mealName: String,
        description: String,
        availableIngredients: [AvailableIngredient]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let input = MealAILogInput(
            mealName: mealName.isEmpty ? nil : mealName,
            mealDescription: description,
            availableIngredientsList: availableIngredients
        )
        guard let data = try? encoder.encode(input),
              let text = String(data: data, encoding: .utf8) else {
            return "Failed to encode AI meal log input payload."
        }
        return text
    }

    private func makeTodaySoFarInputLog(input: InsightGenerationInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(input),
              let text = String(data: data, encoding: .utf8) else {
            return "Failed to encode day summary AI input payload."
        }
        return text
    }

    enum AILogPhase {
        case idle
        case processing
        case success
        case failure
    }
}

private struct CachedTodaySoFar {
    let content: String
    let providerLabel: String
    let mealSignature: String
}
