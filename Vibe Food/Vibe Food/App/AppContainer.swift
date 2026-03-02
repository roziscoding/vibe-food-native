import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    let modelContainer: ModelContainer
    let ingredientRepository: IngredientRepository
    let mealRepository: MealRepository
    let settingsRepository: SettingsRepository
    let aiIntegrationRepository: AIIntegrationRepository
    let insightRepository: InsightRepository
    let resetService: ResetService

    var deviceId: String {
        deviceIdentityStore.deviceId
    }

    private let deviceIdentityStore: DeviceIdentityStore

    init(deviceIdentityStore: DeviceIdentityStore? = nil) {
        self.deviceIdentityStore = deviceIdentityStore ?? UserDefaultsDeviceIdentityStore()

        let schema = Schema([
            IngredientRecord.self,
            MealRecord.self,
            MealIngredientSnapshotRecord.self,
            SettingsRecord.self,
            AIIntegrationRecord.self,
            InsightRecord.self
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
        settingsRepository = SwiftDataSettingsRepository(context: context)
        aiIntegrationRepository = SwiftDataAIIntegrationRepository(context: context)
        insightRepository = SwiftDataInsightRepository(context: context)
        resetService = ResetService(context: context)
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
}
