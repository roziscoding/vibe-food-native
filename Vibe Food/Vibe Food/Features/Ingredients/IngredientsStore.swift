import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class IngredientsStore {
    private let repository: IngredientRepository
    private let aiIntegrationRepository: AIIntegrationRepository
    private let deviceId: String
    private let derivationService = NutritionDerivationService()
    private let importService = IngredientImportService()
    private let scanService = LabelScanService()

    var ingredients: [IngredientRecord] = []
    var searchText: String = ""
    var draft: IngredientDraft?
    var editingIngredientId: UUID?
    var fieldErrors: [String: String] = [:]
    var draftError: String?
    var errorMessage: String?
    var isPresentingEditor: Bool = false
    var isPresentingImportSheet: Bool = false
    var isPresentingFileImporter: Bool = false
    var importJSONText: String = ""
    var isPresentingScanSource: Bool = false
    var isPresentingCamera: Bool = false
    var isPresentingPhotoPicker: Bool = false
    var isProcessingScan: Bool = false
    var isPresentingScanStatus: Bool = false
    var scanProviderLabel: String = "Local model"
    var scanOutput: String?
    var scanPhase: ScanPhase = .idle
    var scanError: String?
    var shouldPresentEditorAfterScan: Bool = false
    var pendingDelete: IngredientRecord?
    var exportPayload: ExportPayload?

    init(repository: IngredientRepository, aiIntegrationRepository: AIIntegrationRepository, deviceId: String) {
        self.repository = repository
        self.aiIntegrationRepository = aiIntegrationRepository
        self.deviceId = deviceId
    }

    var filteredIngredients: [IngredientRecord] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ingredients
        }
        return ingredients.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    func load() {
        do {
            ingredients = try repository.fetchActiveIngredients()
        } catch {
            errorMessage = "Failed to load ingredients."
        }
    }

    func beginCreate() {
        editingIngredientId = nil
        draft = IngredientDraft(
            name: "",
            unit: "g",
            portionSize: 1,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0
        )
        isPresentingEditor = true
    }

    func beginEdit(_ ingredient: IngredientRecord) {
        editingIngredientId = ingredient.id
        draft = IngredientDraft(
            id: ingredient.id,
            name: ingredient.name,
            unit: ingredient.unit,
            portionSize: ingredient.portionSize,
            calories: ingredient.caloriesPerPortion,
            protein: ingredient.proteinPerPortion,
            carbs: ingredient.carbsPerPortion,
            fat: ingredient.fatPerPortion
        )
        isPresentingEditor = true
    }

    func cancelEdit() {
        isPresentingEditor = false
        draft = nil
        editingIngredientId = nil
        draftError = nil
        fieldErrors = [:]
    }

    func saveDraft() {
        guard var draft = draft else { return }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        fieldErrors = [:]
        guard !trimmedName.isEmpty else {
            fieldErrors["name"] = "Name is required."
            return
        }
        draft.name = trimmedName
        draft.unit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            let perUnit = try derivationService.derivePerUnit(from: draft)

            if let editingId = editingIngredientId,
               let existing = ingredients.first(where: { $0.id == editingId }) {
                existing.name = draft.name
                existing.unit = draft.unit
                existing.portionSize = draft.portionSize
                existing.caloriesPerPortion = draft.calories
                existing.proteinPerPortion = draft.protein
                existing.carbsPerPortion = draft.carbs
                existing.fatPerPortion = draft.fat
                existing.caloriesPerUnit = perUnit.calories
                existing.proteinPerUnit = perUnit.protein
                existing.carbsPerUnit = perUnit.carbs
                existing.fatPerUnit = perUnit.fat
                existing.touch(updatedBy: deviceId)
                try repository.save()
            } else {
                let record = IngredientRecord(
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
                try repository.insert(record)
            }

            load()
            cancelEdit()
        } catch ValidationError.invalidValue {
            errorMessage = "Please enter valid, non-negative values."
        } catch {
            errorMessage = "Failed to save ingredient."
        }
    }

    func confirmDelete(_ ingredient: IngredientRecord) {
        pendingDelete = ingredient
    }

    func deletePending() {
        guard let ingredient = pendingDelete else { return }
        delete(ingredient)
        pendingDelete = nil
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    func delete(_ ingredient: IngredientRecord) {
        do {
            try repository.softDelete(ingredient)
            load()
        } catch {
            errorMessage = "Failed to delete ingredient."
        }
    }

    func beginImportPaste() {
        importJSONText = ""
        isPresentingImportSheet = true
    }

    func beginImportFile() {
        isPresentingFileImporter = true
    }

    func beginScan() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            isPresentingCamera = true
        } else {
            isPresentingPhotoPicker = true
        }
    }

    func startCameraScan() {
        isPresentingCamera = true
    }

    func startPhotoScan() {
        isPresentingPhotoPicker = true
    }

    func handleScanImage(_ image: UIImage) async {
        scanPhase = .processing
        scanError = nil
        scanOutput = nil
        isPresentingScanStatus = true
        isProcessingScan = true
        defer { isProcessingScan = false }
        do {
            let integration = try? aiIntegrationRepository.fetchIntegration()
            if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scanProviderLabel = integration.provider == .openai ? "OpenAI" : "Anthropic"
            } else {
                scanProviderLabel = "Local model"
            }

            let result = try await scanService.scan(image: image, integration: integration)
            draft = result.draft
            editingIngredientId = nil
            scanOutput = result.outputText
            scanPhase = .success
            shouldPresentEditorAfterScan = true
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                scanError = description
            } else {
                scanError = "Failed to scan label. \(error)"
            }
            scanPhase = .failure
        }
    }

    func dismissScanStatus() {
        isPresentingScanStatus = false
        if scanPhase == .success, shouldPresentEditorAfterScan {
            isPresentingEditor = true
        }
        shouldPresentEditorAfterScan = false
        if scanPhase != .processing {
            scanPhase = .idle
        }
    }

    enum ScanPhase {
        case idle
        case processing
        case success
        case failure
    }

    func importFromJSONText() {
        let trimmed = importJSONText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            errorMessage = "Paste valid JSON to import."
            return
        }
        importFromData(data)
    }

    func importFromData(_ data: Data) {
        do {
            let importedDraft = try importService.parse(data: data)
            draft = importedDraft
            editingIngredientId = nil
            isPresentingImportSheet = false
            isPresentingEditor = true
        } catch {
            errorMessage = "Failed to parse ingredient JSON."
        }
    }

    func prepareExport() {
        do {
            let rows = ingredients
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { IngredientExportRow(name: $0.name, uuid: $0.id.uuidString, unit: $0.unit) }
            let data = try JSONEncoder().encode(rows)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vibe-food-ingredients.json")
            try data.write(to: url, options: .atomic)
            exportPayload = ExportPayload(url: url)
        } catch {
            errorMessage = "Failed to export ingredients."
        }
    }
}
