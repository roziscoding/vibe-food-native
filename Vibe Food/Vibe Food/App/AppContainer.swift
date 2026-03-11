import Combine
import Foundation
import os
import SwiftData
import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    let modelContainer: ModelContainer
    let ingredientRepository: IngredientRepository
    let mealRepository: MealRepository
    let waterRepository: WaterRepository
    let settingsRepository: SettingsRepository
    let aiIntegrationRepository: AIIntegrationRepository
    let insightRepository: InsightRepository
    let todaySoFarRepository: TodaySoFarRepository
    let resetService: ResetService
    let settingsStore: SettingsStore
    let ingredientsStore: IngredientsStore
    let daySelectionStore: DaySelectionStore
    @Published var selectedTab: AppTab = .input

    var deviceId: String {
        deviceIdentityStore.deviceId
    }

    private let deviceIdentityStore: DeviceIdentityStore
    private let commandLogger = Logger(subsystem: "ninja.roz.vibefood", category: "Commands")
    private let derivationService = NutritionDerivationService()
    private var didHandleLaunchCommand = false

    init(deviceIdentityStore: DeviceIdentityStore? = nil) {
        self.deviceIdentityStore = deviceIdentityStore ?? UserDefaultsDeviceIdentityStore()
        self.daySelectionStore = DaySelectionStore()

        let schema = Schema([
            IngredientRecord.self,
            MealRecord.self,
            WaterEntryRecord.self,
            MealIngredientSnapshotRecord.self,
            SettingsRecord.self,
            AIIntegrationRecord.self,
            InsightRecord.self,
            TodaySoFarRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let context = modelContainer.mainContext
        ingredientRepository = SwiftDataIngredientRepository(context: context)
        mealRepository = SwiftDataMealRepository(context: context)
        waterRepository = SwiftDataWaterRepository(context: context)
        settingsRepository = SwiftDataSettingsRepository(context: context)
        aiIntegrationRepository = SwiftDataAIIntegrationRepository(context: context)
        insightRepository = SwiftDataInsightRepository(context: context)
        todaySoFarRepository = SwiftDataTodaySoFarRepository(context: context)
        resetService = ResetService(context: context)

        settingsStore = SettingsStore(
            repository: settingsRepository,
            aiRepository: aiIntegrationRepository,
            context: context,
            deviceId: self.deviceIdentityStore.deviceId
        )
        ingredientsStore = IngredientsStore(
            repository: ingredientRepository,
            aiIntegrationRepository: aiIntegrationRepository,
            deviceId: self.deviceIdentityStore.deviceId
        )
    }

    func resetAllData() throws {
        try resetService.resetAllData { [weak self] in
            self?.seedIfNeeded()
        }
    }

    func seedIfNeeded() {
        let context = modelContainer.mainContext
        do {
            let settingsFetch = FetchDescriptor<SettingsRecord>(
                predicate: #Predicate { $0.id == "settings" }
            )
            if try context.fetch(settingsFetch).isEmpty {
                let deviceId = deviceIdentityStore.deviceId
                let settings = SettingsRecord(
                    calorieGoal: 2000,
                    proteinGoal: 150,
                    carbsGoal: 250,
                    fatGoal: 70,
                    waterGoal: 2000,
                    showsInsights: true,
                    showsTodaySoFarBanner: true,
                    lastModifiedByDeviceId: deviceId
                )
                context.insert(settings)
            }

            let aiFetch = FetchDescriptor<AIIntegrationRecord>(
                predicate: #Predicate { $0.id == "ai-integration" }
            )
            if try context.fetch(aiFetch).isEmpty {
                let deviceId = deviceIdentityStore.deviceId
                let integration = AIIntegrationRecord(
                    provider: .openai,
                    apiKey: "",
                    lastModifiedByDeviceId: deviceId
                )
                context.insert(integration)
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            print("Seed failed: \(error)")
        }
    }

    func handleCommandURL(_ url: URL) {
        do {
            let command = try AppCommandParser.parse(url: url)
            let summary = try perform(command)
            commandLogger.info(
                "Handled command url=\(url.absoluteString, privacy: .public) summary=\(summary, privacy: .public)"
            )
        } catch {
            commandLogger.error(
                "Failed command url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func handleLaunchArguments(_ arguments: [String], environment: [String: String]) {
        guard !didHandleLaunchCommand else { return }
        didHandleLaunchCommand = true

        do {
            guard let command = try AppCommandParser.parse(arguments: arguments, environment: environment) else {
                return
            }
            let summary = try perform(command)
            commandLogger.info("Handled launch command summary=\(summary, privacy: .public)")
        } catch {
            commandLogger.error(
                "Failed launch command arguments=\(arguments.joined(separator: " "), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func perform(_ command: AppCommand) throws -> String {
        switch command {
        case .selectTab(let tab):
            selectedTab = tab
            return "Switched to tab '\(tab.rawValue)'."

        case .setDay(let dayCommand):
            switch dayCommand {
            case .today:
                daySelectionStore.goToToday()
            case .previous:
                daySelectionStore.goToPreviousDay()
            case .next:
                daySelectionStore.goToNextDay()
            case .specific(let date):
                daySelectionStore.setSelectedDate(date)
            }
            return "Selected day '\(daySelectionStore.localDayKey)'."

        case .addWater(let amountMl, let date):
            let result = try addWater(amountMl: amountMl, selectedDate: date ?? daySelectionStore.selectedDate)
            return "Logged \(result.amountMl.formatted(.number)) ml for day \(result.localDayKey)."

        case .addMeal(let name, let calories, let protein, let carbs, let fat, let date):
            let result = try addMeal(
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                selectedDate: date ?? daySelectionStore.selectedDate
            )
            return "Logged meal '\(result.name)' for day \(result.localDayKey)."

        case .addIngredient(let name, let unit, let portionSize, let calories, let protein, let carbs, let fat):
            let ingredientName = try addIngredient(
                name: name,
                unit: unit,
                portionSize: portionSize,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            )
            return "Added ingredient '\(ingredientName)'."
        }
    }

    private func addWater(amountMl: Double, selectedDate: Date) throws -> (amountMl: Double, localDayKey: String) {
        let consumedAt = logDate(for: selectedDate)
        let localDayKey = LocalDayKey.key(for: consumedAt, timeZone: .current)
        let normalizedAmount = amountMl.rounded()

        let entry = WaterEntryRecord(
            amountMl: normalizedAmount,
            consumedAt: consumedAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            localDayKey: localDayKey,
            lastModifiedByDeviceId: deviceId
        )
        try waterRepository.insert(entry)
        AppDataChangeNotifier.post(.water)
        return (normalizedAmount, localDayKey)
    }

    private func addMeal(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        selectedDate: Date
    ) throws -> (name: String, localDayKey: String) {
        let consumedAt = logDate(for: selectedDate)
        let localDayKey = LocalDayKey.key(for: consumedAt, timeZone: .current)
        let rounded = NutritionRounding.round(
            MacroBreakdown(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            )
        )

        let meal = MealRecord(
            name: name,
            calories: rounded.calories,
            protein: rounded.protein,
            carbs: rounded.carbs,
            fat: rounded.fat,
            consumedAt: consumedAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            localDayKey: localDayKey,
            lastModifiedByDeviceId: deviceId
        )
        try mealRepository.insert(meal)
        AppDataChangeNotifier.post(.meals)
        return (meal.name, localDayKey)
    }

    private func addIngredient(
        name: String,
        unit: String,
        portionSize: Double,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) throws -> String {
        var draft = IngredientDraft(
            name: name,
            unit: unit.lowercased(),
            portionSize: portionSize,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
        draft = NutritionRounding.round(draft)
        let perUnit = try derivationService.derivePerUnit(from: draft)

        let ingredient = IngredientRecord(
            name: draft.name,
            unit: draft.unit,
            portionSize: draft.portionSize,
            caloriesPerPortion: draft.calories,
            proteinPerPortion: draft.protein,
            carbsPerPortion: draft.carbs,
            fatPerPortion: draft.fat,
            caloriesPerUnit: perUnit.calories,
            proteinPerUnit: perUnit.protein,
            carbsPerUnit: perUnit.carbs,
            fatPerUnit: perUnit.fat,
            lastModifiedByDeviceId: deviceId
        )
        try ingredientRepository.insert(ingredient)
        AppDataChangeNotifier.post(.ingredients)
        return ingredient.name
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
}
