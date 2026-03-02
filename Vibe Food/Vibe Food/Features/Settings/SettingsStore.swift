import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let repository: SettingsRepository
    private let aiRepository: AIIntegrationRepository
    private let deviceId: String
    private let recommendationService = GoalRecommendationService()

    var calorieGoal: Double = 0
    var proteinGoal: Double = 0
    var carbsGoal: Double = 0
    var fatGoal: Double = 0
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
    var aiProvider: AIProvider = .openai
    var aiApiKey: String = ""
    var errorMessage: String?

    init(repository: SettingsRepository, aiRepository: AIIntegrationRepository, deviceId: String) {
        self.repository = repository
        self.aiRepository = aiRepository
        self.deviceId = deviceId
    }

    func load() {
        do {
            if let settings = try repository.fetchSettings() {
                calorieGoal = settings.calorieGoal
                proteinGoal = settings.proteinGoal
                carbsGoal = settings.carbsGoal
                fatGoal = settings.fatGoal
                age = settings.age ?? 18
                heightCm = settings.heightCm ?? 170
                weightKg = settings.weightKg ?? 70
                sex = settings.sex ?? .female
                activityLevel = settings.activityLevel ?? .active
                objective = settings.objective ?? .maintainWeight
            }
            if let integration = try aiRepository.fetchIntegration() {
                aiProvider = integration.provider
                aiApiKey = integration.apiKey
            }
        } catch {
            errorMessage = "Failed to load goals."
        }
    }

    func save() {
        do {
            if let settings = try repository.fetchSettings() {
                settings.calorieGoal = calorieGoal
                settings.proteinGoal = proteinGoal
                settings.carbsGoal = carbsGoal
                settings.fatGoal = fatGoal
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
            errorMessage = "Failed to save goals."
        }
    }

    func saveAI() {
        do {
            if let integration = try aiRepository.fetchIntegration() {
                integration.provider = aiProvider
                integration.apiKey = aiApiKey
                integration.touch(updatedBy: deviceId)
                try aiRepository.save()
            } else {
                let integration = AIIntegrationRecord(
                    provider: aiProvider,
                    apiKey: aiApiKey,
                    lastModifiedByDeviceId: deviceId
                )
                try aiRepository.insert(integration)
            }
        } catch {
            errorMessage = "Failed to save AI settings."
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
    }

    func applyProfile(input: GoalRecommendationInput) {
        age = input.age
        heightCm = input.heightCm
        weightKg = input.weightKg
        sex = input.sex
        activityLevel = input.activityLevel
        objective = input.objective
    }
}
