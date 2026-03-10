import Foundation
import Observation
import SwiftData
import os

@MainActor
@Observable
final class SettingsStore {
    private let repository: SettingsRepository
    private let aiRepository: AIIntegrationRepository
    private let context: ModelContext
    private let deviceId: String
    private let logger = Logger(subsystem: "ninja.roz.vibefood", category: "SettingsStore")
    private var hasLoadedOnce: Bool = false
    private let recommendationService = GoalRecommendationService()
    private let aiProviderCreditService = AIProviderCreditService()

    var calorieGoal: Double = 0
    var proteinGoal: Double = 0
    var carbsGoal: Double = 0
    var fatGoal: Double = 0
    var waterGoal: Double = 2000
    var quickWaterAmount1: Double = WaterQuickAmountsConfig.defaultValues[0]
    var quickWaterAmount2: Double = WaterQuickAmountsConfig.defaultValues[1]
    var quickWaterAmount3: Double = WaterQuickAmountsConfig.defaultValues[2]
    var showsInsights: Bool = true
    var showsTodaySoFarBanner: Bool = true
    var age: Int = 18
    var heightCm: Double = 170
    var weightKg: Double = 70
    var sex: Sex = .female
    var activityLevel: ActivityLevel = .active
    var objective: GoalObjective = .maintainWeight

    var showRecommendation: Bool = false
    var showProfileEditor: Bool = false
    var showResetConfirm: Bool = false
    var showResetFinal: Bool = false
    var isPresentingBackupImporter: Bool = false
    var aiProvider: AIProvider = .openai
    var aiApiKey: String = ""
    var aiApiKeyDraft: String = ""
    var aiCreditDisplayText: String?
    var aiCreditErrorMessage: String?
    var isConfirmingAIKey: Bool = false
    var isEditingAIKey: Bool = true
    var backupExportPayload: ExportPayload?
    var errorMessage: String?

    init(repository: SettingsRepository, aiRepository: AIIntegrationRepository, context: ModelContext, deviceId: String) {
        self.repository = repository
        self.aiRepository = aiRepository
        self.context = context
        self.deviceId = deviceId
    }

    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        load()
    }

    func load() {
        logger.info("load() started.")
        do {
            let fetchedSettings = try repository.fetchSettings()
            logger.info("fetchSettings completed. found=\(fetchedSettings != nil, privacy: .public)")
            if let settings = fetchedSettings {
                calorieGoal = settings.calorieGoal
                proteinGoal = settings.proteinGoal
                carbsGoal = settings.carbsGoal
                fatGoal = settings.fatGoal
                waterGoal = settings.waterGoal ?? 2000
                applyQuickWaterAmounts(csv: settings.waterQuickAmountsCsv)
                showsInsights = settings.showsInsights ?? true
                showsTodaySoFarBanner = settings.showsTodaySoFarBanner ?? true
                age = settings.age ?? 18
                heightCm = settings.heightCm ?? 170
                weightKg = settings.weightKg ?? 70
                sex = settings.sex ?? .female
                activityLevel = settings.activityLevel ?? .active
                objective = settings.objective ?? .maintainWeight
            }
            let fetchedIntegration = try aiRepository.fetchIntegration()
            logger.info("fetchIntegration completed. found=\(fetchedIntegration != nil, privacy: .public)")
            if let integration = fetchedIntegration {
                aiProvider = integration.provider
                aiApiKey = integration.apiKey
                aiApiKeyDraft = ""
                aiCreditDisplayText = integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : "API key configured."
                aiCreditErrorMessage = nil
                isEditingAIKey = integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else {
                aiApiKey = ""
                aiApiKeyDraft = ""
                aiCreditDisplayText = nil
                aiCreditErrorMessage = nil
                isEditingAIKey = true
            }
            hasLoadedOnce = true
            logger.info("load() finished successfully.")
        } catch {
            logger.error("load() failed: \(error.localizedDescription, privacy: .public)")
            setError("Failed to load goals.", operation: "Load settings", error: error)
        }
    }

    func save() {
        do {
            if let settings = try repository.fetchSettings() {
                settings.calorieGoal = calorieGoal
                settings.proteinGoal = proteinGoal
                settings.carbsGoal = carbsGoal
                settings.fatGoal = fatGoal
                settings.waterGoal = waterGoal
                settings.waterQuickAmountsCsv = WaterQuickAmountsConfig.serialize(quickWaterAmounts)
                settings.showsInsights = showsInsights
                settings.showsTodaySoFarBanner = showsTodaySoFarBanner
                settings.age = age
                settings.heightCm = heightCm
                settings.weightKg = weightKg
                settings.sex = sex
                settings.activityLevel = activityLevel
                settings.objective = objective
                settings.touch(updatedBy: deviceId)
                try repository.save()
            } else {
                let settings = SettingsRecord(
                    calorieGoal: calorieGoal,
                    proteinGoal: proteinGoal,
                    carbsGoal: carbsGoal,
                    fatGoal: fatGoal,
                    waterGoal: waterGoal,
                    waterQuickAmountsCsv: WaterQuickAmountsConfig.serialize(quickWaterAmounts),
                    showsInsights: showsInsights,
                    showsTodaySoFarBanner: showsTodaySoFarBanner,
                    age: age,
                    heightCm: heightCm,
                    weightKg: weightKg,
                    sex: sex,
                    activityLevel: activityLevel,
                    objective: objective,
                    lastModifiedByDeviceId: deviceId
                )
                try repository.insert(settings)
            }
        } catch {
            setError("Failed to save goals.", operation: "Save settings", error: error)
        }
        AppDataChangeNotifier.post(.settings)
    }

    func saveAI() {
        let normalizedKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let integration = try aiRepository.fetchIntegration() {
                integration.provider = aiProvider
                integration.apiKey = normalizedKey
                integration.touch(updatedBy: deviceId)
                try aiRepository.save()
            } else {
                let integration = AIIntegrationRecord(
                    provider: aiProvider,
                    apiKey: normalizedKey,
                    lastModifiedByDeviceId: deviceId
                )
                try aiRepository.insert(integration)
            }
        } catch {
            setError("Failed to save AI settings.", operation: "Save AI settings", error: error)
        }
        AppDataChangeNotifier.post(.settings)
    }

    func aiProviderChanged() {
        aiCreditDisplayText = nil
        aiCreditErrorMessage = nil
        aiApiKeyDraft = ""
        isEditingAIKey = true
        saveAI()
    }

    func beginChangingAIKey() {
        aiApiKeyDraft = ""
        aiCreditDisplayText = nil
        aiCreditErrorMessage = nil
        isEditingAIKey = true
    }

    func clearAIKey() {
        aiApiKey = ""
        aiApiKeyDraft = ""
        aiCreditDisplayText = nil
        aiCreditErrorMessage = nil
        isEditingAIKey = true
        saveAI()
    }

    func confirmAIKey() async {
        let normalizedDraft = aiApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDraft.isEmpty else {
            aiCreditErrorMessage = "Enter an API key first."
            return
        }

        aiCreditErrorMessage = nil
        isConfirmingAIKey = true
        defer { isConfirmingAIKey = false }

        do {
            let result = try await aiProviderCreditService.verifyAndFetchCredit(
                provider: aiProvider,
                apiKey: normalizedDraft
            )
            aiApiKey = normalizedDraft
            aiApiKeyDraft = ""
            aiCreditDisplayText = result.displayText
            aiCreditErrorMessage = nil
            isEditingAIKey = false
            saveAI()
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                aiCreditErrorMessage = description
            } else {
                aiCreditErrorMessage = "Failed to verify API key."
            }
            ErrorReportService.capture(
                key: ErrorReportKey.settingsAICredit,
                feature: "Settings",
                operation: "Verify AI API key",
                userMessage: aiCreditErrorMessage ?? "Failed to verify API key.",
                error: error,
                llmProvider: aiProvider.rawValue.capitalized
            )
        }
    }

    func applyRecommendation(input: GoalRecommendationInput) {
        age = input.age
        heightCm = input.heightCm
        weightKg = input.weightKg
        sex = input.sex
        activityLevel = input.activityLevel
        objective = input.objective
        let output = recommendationService.recommend(from: input)
        calorieGoal = output.targets.calories
        proteinGoal = output.targets.protein
        carbsGoal = output.targets.carbs
        fatGoal = output.targets.fat
        waterGoal = output.waterGoalMl
    }

    func applyProfile(input: GoalRecommendationInput) {
        age = input.age
        heightCm = input.heightCm
        weightKg = input.weightKg
        sex = input.sex
        activityLevel = input.activityLevel
        objective = input.objective
    }

    private var quickWaterAmounts: [Double] {
        WaterQuickAmountsConfig.normalize([
            quickWaterAmount1,
            quickWaterAmount2,
            quickWaterAmount3
        ])
    }

    private func applyQuickWaterAmounts(csv: String?) {
        let quickWaterAmounts = WaterQuickAmountsConfig.parse(csv: csv)
        quickWaterAmount1 = quickWaterAmounts[0]
        quickWaterAmount2 = quickWaterAmounts[1]
        quickWaterAmount3 = quickWaterAmounts[2]
    }

    func exportAllData() {
        do {
            let ingredients = try fetchActiveIngredients()
            let meals = try fetchActiveMeals()
            let waterEntries = try fetchActiveWaterEntries()
            let settings = try repository.fetchSettings()
            let aiIntegration = try aiRepository.fetchIntegration()

            let payload = AppDataBackupPayload(
                schemaVersion: 1,
                exportedAt: Date(),
                ingredients: ingredients.map { ingredient in
                    IngredientBackupRow(
                        id: ingredient.id,
                        name: ingredient.name,
                        unit: ingredient.unit,
                        portionSize: ingredient.portionSize,
                        caloriesPerPortion: ingredient.caloriesPerPortion,
                        proteinPerPortion: ingredient.proteinPerPortion,
                        carbsPerPortion: ingredient.carbsPerPortion,
                        fatPerPortion: ingredient.fatPerPortion,
                        caloriesPerUnit: ingredient.caloriesPerUnit,
                        proteinPerUnit: ingredient.proteinPerUnit,
                        carbsPerUnit: ingredient.carbsPerUnit,
                        fatPerUnit: ingredient.fatPerUnit,
                        createdAt: ingredient.createdAt,
                        updatedAt: ingredient.updatedAt,
                        lastModifiedByDeviceId: ingredient.lastModifiedByDeviceId,
                        syncVersion: ingredient.syncVersion
                    )
                },
                meals: meals.map { meal in
                    MealBackupRow(
                        id: meal.id,
                        name: meal.name,
                        calories: meal.calories,
                        protein: meal.protein,
                        carbs: meal.carbs,
                        fat: meal.fat,
                        consumedAt: meal.consumedAt,
                        timeZoneIdentifier: meal.timeZoneIdentifier,
                        localDayKey: meal.localDayKey,
                        createdAt: meal.createdAt,
                        updatedAt: meal.updatedAt,
                        lastModifiedByDeviceId: meal.lastModifiedByDeviceId,
                        syncVersion: meal.syncVersion,
                        ingredientSnapshots: meal.ingredientSnapshots.map { snapshot in
                            MealBackupRow.Snapshot(
                                id: snapshot.id,
                                sourceIngredientID: snapshot.sourceIngredientID,
                                name: snapshot.name,
                                amount: snapshot.amount,
                                unit: snapshot.unit
                            )
                        }
                    )
                },
                waterEntries: waterEntries.map { entry in
                    WaterEntryBackupRow(
                        id: entry.id,
                        amountMl: entry.amountMl,
                        consumedAt: entry.consumedAt,
                        timeZoneIdentifier: entry.timeZoneIdentifier,
                        localDayKey: entry.localDayKey,
                        createdAt: entry.createdAt,
                        updatedAt: entry.updatedAt,
                        lastModifiedByDeviceId: entry.lastModifiedByDeviceId,
                        syncVersion: entry.syncVersion
                    )
                },
                settings: settings.map { settings in
                    SettingsBackupRow(
                        calorieGoal: settings.calorieGoal,
                        proteinGoal: settings.proteinGoal,
                        carbsGoal: settings.carbsGoal,
                        fatGoal: settings.fatGoal,
                        waterGoal: settings.waterGoal,
                        waterQuickAmountsCsv: settings.waterQuickAmountsCsv,
                        showsInsights: settings.showsInsights,
                        showsTodaySoFarBanner: settings.showsTodaySoFarBanner,
                        age: settings.age,
                        heightCm: settings.heightCm,
                        weightKg: settings.weightKg,
                        sex: settings.sex,
                        activityLevel: settings.activityLevel,
                        objective: settings.objective,
                        createdAt: settings.createdAt,
                        updatedAt: settings.updatedAt,
                        lastModifiedByDeviceId: settings.lastModifiedByDeviceId,
                        syncVersion: settings.syncVersion
                    )
                },
                aiIntegration: aiIntegration.map { integration in
                    AIIntegrationBackupRow(
                        provider: integration.provider,
                        apiKey: integration.apiKey,
                        updatedAt: integration.updatedAt,
                        lastModifiedByDeviceId: integration.lastModifiedByDeviceId,
                        syncVersion: integration.syncVersion
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vibe-food-backup.json")
            try data.write(to: url, options: .atomic)
            backupExportPayload = ExportPayload(url: url)
        } catch {
            setError("Failed to export data backup.", operation: "Export app data backup", error: error)
        }
    }

    func importAllData(from data: Data) {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(AppDataBackupPayload.self, from: data)
            guard payload.schemaVersion == 1 else {
                setError("Unsupported backup version.", operation: "Import app data backup")
                return
            }

            try clearImportTargets()

            for ingredient in payload.ingredients {
                context.insert(IngredientRecord(
                    id: ingredient.id,
                    name: ingredient.name,
                    unit: ingredient.unit,
                    portionSize: ingredient.portionSize,
                    caloriesPerPortion: ingredient.caloriesPerPortion,
                    proteinPerPortion: ingredient.proteinPerPortion,
                    carbsPerPortion: ingredient.carbsPerPortion,
                    fatPerPortion: ingredient.fatPerPortion,
                    caloriesPerUnit: ingredient.caloriesPerUnit,
                    proteinPerUnit: ingredient.proteinPerUnit,
                    carbsPerUnit: ingredient.carbsPerUnit,
                    fatPerUnit: ingredient.fatPerUnit,
                    createdAt: ingredient.createdAt,
                    updatedAt: ingredient.updatedAt,
                    lastModifiedByDeviceId: ingredient.lastModifiedByDeviceId,
                    syncVersion: ingredient.syncVersion
                ))
            }

            for meal in payload.meals {
                let snapshots = meal.ingredientSnapshots.map { snapshot in
                    MealIngredientSnapshotRecord(
                        id: snapshot.id,
                        sourceIngredientID: snapshot.sourceIngredientID,
                        name: snapshot.name,
                        amount: snapshot.amount,
                        unit: snapshot.unit
                    )
                }
                context.insert(MealRecord(
                    id: meal.id,
                    name: meal.name,
                    calories: meal.calories,
                    protein: meal.protein,
                    carbs: meal.carbs,
                    fat: meal.fat,
                    consumedAt: meal.consumedAt,
                    timeZoneIdentifier: meal.timeZoneIdentifier,
                    localDayKey: meal.localDayKey,
                    createdAt: meal.createdAt,
                    updatedAt: meal.updatedAt,
                    lastModifiedByDeviceId: meal.lastModifiedByDeviceId,
                    syncVersion: meal.syncVersion,
                    ingredientSnapshots: snapshots
                ))
            }

            for waterEntry in payload.waterEntries ?? [] {
                context.insert(WaterEntryRecord(
                    id: waterEntry.id,
                    amountMl: waterEntry.amountMl,
                    consumedAt: waterEntry.consumedAt,
                    timeZoneIdentifier: waterEntry.timeZoneIdentifier,
                    localDayKey: waterEntry.localDayKey,
                    createdAt: waterEntry.createdAt,
                    updatedAt: waterEntry.updatedAt,
                    lastModifiedByDeviceId: waterEntry.lastModifiedByDeviceId,
                    syncVersion: waterEntry.syncVersion
                ))
            }

            if let settings = payload.settings {
                context.insert(SettingsRecord(
                    calorieGoal: settings.calorieGoal,
                    proteinGoal: settings.proteinGoal,
                    carbsGoal: settings.carbsGoal,
                    fatGoal: settings.fatGoal,
                    waterGoal: settings.waterGoal ?? 2000,
                    waterQuickAmountsCsv: settings.waterQuickAmountsCsv,
                    showsInsights: settings.showsInsights,
                    showsTodaySoFarBanner: settings.showsTodaySoFarBanner,
                    age: settings.age,
                    heightCm: settings.heightCm,
                    weightKg: settings.weightKg,
                    sex: settings.sex,
                    activityLevel: settings.activityLevel,
                    objective: settings.objective,
                    createdAt: settings.createdAt,
                    updatedAt: settings.updatedAt,
                    lastModifiedByDeviceId: settings.lastModifiedByDeviceId,
                    syncVersion: settings.syncVersion
                ))
            }

            if let integration = payload.aiIntegration {
                context.insert(AIIntegrationRecord(
                    provider: integration.provider,
                    apiKey: integration.apiKey,
                    updatedAt: integration.updatedAt,
                    lastModifiedByDeviceId: integration.lastModifiedByDeviceId,
                    syncVersion: integration.syncVersion
                ))
            }

            if context.hasChanges {
                try context.save()
            }
            load()
            AppDataChangeNotifier.post(.ingredients)
            AppDataChangeNotifier.post(.meals)
            AppDataChangeNotifier.post(.water)
            AppDataChangeNotifier.post(.settings)
        } catch {
            setError("Failed to import backup: \(error.localizedDescription)", operation: "Import app data backup", error: error)
        }
    }

    private func fetchActiveIngredients() throws -> [IngredientRecord] {
        let descriptor = FetchDescriptor<IngredientRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\IngredientRecord.name)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchActiveMeals() throws -> [MealRecord] {
        let descriptor = FetchDescriptor<MealRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\MealRecord.consumedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchActiveWaterEntries() throws -> [WaterEntryRecord] {
        let descriptor = FetchDescriptor<WaterEntryRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\WaterEntryRecord.consumedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func clearImportTargets() throws {
        let ingredients = try context.fetch(FetchDescriptor<IngredientRecord>())
        ingredients.forEach { context.delete($0) }

        let meals = try context.fetch(FetchDescriptor<MealRecord>())
        meals.forEach { context.delete($0) }

        let waterEntries = try context.fetch(FetchDescriptor<WaterEntryRecord>())
        waterEntries.forEach { context.delete($0) }

        let settings = try context.fetch(FetchDescriptor<SettingsRecord>())
        settings.forEach { context.delete($0) }

        let integrations = try context.fetch(FetchDescriptor<AIIntegrationRecord>())
        integrations.forEach { context.delete($0) }
    }

    private func setError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.settingsAlert,
            feature: "Settings",
            operation: operation,
            userMessage: message,
            error: error
        )
    }
}
