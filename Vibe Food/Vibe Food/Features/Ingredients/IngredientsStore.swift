import Foundation
import Observation
import UIKit
import os

@MainActor
@Observable
final class IngredientsStore {
    private let repository: IngredientRepository
    private let aiIntegrationRepository: AIIntegrationRepository
    private let deviceId: String
    private let logger = Logger(subsystem: "ninja.roz.vibefood", category: "IngredientsStore")
    private var hasLoadedOnce: Bool = false
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

    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        load()
    }

    func load() {
        logger.info("load() started.")
        do {
            ingredients = try repository.fetchActiveIngredients()
            hasLoadedOnce = true
            logger.info("load() finished. ingredientCount=\(self.ingredients.count, privacy: .public)")
        } catch {
            logger.error("load() failed: \(error.localizedDescription, privacy: .public)")
            setAlertError("Failed to load ingredients.", operation: "Load ingredients", error: error)
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
            calories: NutritionRounding.roundCalories(ingredient.caloriesPerPortion),
            protein: NutritionRounding.roundMacro(ingredient.proteinPerPortion),
            carbs: NutritionRounding.roundMacro(ingredient.carbsPerPortion),
            fat: NutritionRounding.roundMacro(ingredient.fatPerPortion)
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
        draft = NutritionRounding.round(draft)
        self.draft = draft

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
            AppDataChangeNotifier.post(.ingredients)
        } catch ValidationError.invalidValue {
            setAlertError("Please enter valid, non-negative values.", operation: "Save ingredient validation")
        } catch {
            setAlertError("Failed to save ingredient.", operation: "Save ingredient", error: error)
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
            AppDataChangeNotifier.post(.ingredients)
        } catch {
            setAlertError("Failed to delete ingredient.", operation: "Delete ingredient", error: error)
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
        var scanInput = "Notes: User-selected nutrition label image"
        do {
            let integration = try? aiIntegrationRepository.fetchIntegration()
            if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scanProviderLabel = integration.provider == .openai ? "OpenAI" : "Anthropic"
            } else {
                scanProviderLabel = "Local model"
            }
            scanInput = """
            Provider: \(scanProviderLabel)
            Image size: \(Int(image.size.width))x\(Int(image.size.height))
            Notes: User-selected nutrition label image
            """

            let result = try await scanService.scan(image: image, integration: integration)
            draft = NutritionRounding.round(result.draft)
            editingIngredientId = nil
            scanOutput = result.outputText
            scanPhase = .success
            shouldPresentEditorAfterScan = true
            dismissScanStatus()
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                scanError = description
            } else {
                scanError = "Failed to scan label. \(error)"
            }
            ErrorReportService.capture(
                key: ErrorReportKey.ingredientsScan,
                feature: "Ingredients",
                operation: "Scan nutrition label",
                userMessage: scanError ?? "Scan failed.",
                error: error,
                llmInput: scanInput,
                llmOutput: scanOutput,
                llmProvider: scanProviderLabel
            )
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
            setAlertError("Paste valid JSON to import.", operation: "Import ingredient JSON text")
            return
        }
        importFromData(data)
    }

    func importFromData(_ data: Data) {
        do {
            let importedDraft = try importService.parse(data: data)
            draft = NutritionRounding.round(importedDraft)
            editingIngredientId = nil
            isPresentingImportSheet = false
            isPresentingEditor = true
        } catch {
            setAlertError("Failed to parse ingredient JSON.", operation: "Parse ingredient JSON import", error: error)
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
            setAlertError("Failed to export ingredients.", operation: "Export ingredients", error: error)
        }
    }

    private func setAlertError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.ingredientsAlert,
            feature: "Ingredients",
            operation: operation,
            userMessage: message,
            error: error
        )
    }
}
