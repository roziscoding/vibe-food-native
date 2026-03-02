import Foundation
import FoundationModels
import Vision
import UIKit

@Generable(description: "Datos de una etiqueta nutricional en espanol")
struct NutritionLabelDraft: Codable {
    @Guide(description: "Nombre del producto")
    var productName: String

    @Guide(description: "Unidad de porcion, por ejemplo g, ml, pieza")
    var portionUnit: String

    @Guide(description: "Tamano de porcion")
    var portionSize: Double

    @Guide(description: "Calorias por porcion")
    var calories: Double

    @Guide(description: "Proteinas en gramos por porcion")
    var proteinG: Double

    @Guide(description: "Carbohidratos en gramos por porcion")
    var carbohydratesG: Double

    @Guide(description: "Grasas totales en gramos por porcion")
    var totalFatG: Double
}

struct LabelScanService {
    struct ScanResult {
        let draft: IngredientDraft
        let outputText: String?
    }

    private struct RemoteParseResult {
        let draft: NutritionLabelDraft
        let rawText: String?
    }

    private struct OpenAILabelOutput: Decodable {
        struct Macros: Decodable {
            let proteinG: Double
            let carbohydratesG: Double
            let totalFatG: Double

            private enum CodingKeys: String, CodingKey {
                case proteinG = "protein_g"
                case carbohydratesG = "carbohydrates_g"
                case totalFatG = "total_fat_g"
            }
        }

        let productName: String
        let calories: Double
        let portionSize: Double
        let portionUnit: String
        let macros: Macros

        private enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case calories
            case portionSize = "portion_size"
            case portionUnit = "portion_unit"
            case macros = "macros_per_portion"
        }
    }

    func scan(image: UIImage, integration: AIIntegrationRecord?) async throws -> ScanResult {
        guard let cgImage = image.cgImage else {
            throw ScanError.invalidImage
        }

        let draft: NutritionLabelDraft
        let outputText: String?
        if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result = try await parseWithRemoteModel(image: image, integration: integration)
            draft = result.draft
            outputText = result.rawText
        } else {
            let text = try await recognizeText(from: cgImage)
            draft = try await parseNutritionLabel(text: text)
            outputText = encodeDraftJSON(draft)
        }

        let ingredientDraft = IngredientDraft(
            name: draft.productName,
            unit: draft.portionUnit.lowercased(),
            portionSize: draft.portionSize,
            calories: draft.calories,
            protein: draft.proteinG,
            carbs: draft.carbohydratesG,
            fat: draft.totalFatG
        )
        return ScanResult(draft: ingredientDraft, outputText: outputText)
    }

    private func recognizeText(from cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: strings.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["es-ES"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func parseNutritionLabel(text: String) async throws -> NutritionLabelDraft {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ScanError.modelUnavailable
        }

        let instructions = """
        Objective

        Extract nutritional information from the provided image of a nutrition facts label. Identify the product name (if visible), serving size information, calories, and specific macronutrients per serving.

        Instructions
        1. Analyze the image provided in nutrition_table_image.
        2. Extract the following information:
        - Product Name: Look for the name of the ingredient or product. If not explicitly present in the image, return "-".
        - Calories: Total energy/calories per serving.
        - Portion Size: The numeric value of the serving size (e.g., 30).
        - Portion Unit: The unit of measurement for the serving size (e.g., g, ml, tbsp).
        - Macronutrients: Extract the values (in grams) per portion for Protein, Total Carbohydrates, and Total Fat.
        3. Output JSON only (no markdown fences, no explanation) using the schema below.

        Observations
        - Ensure all macronutrient values are strictly numbers representing grams. If a value is missing or zero, treat it as 0 unless specified otherwise.
        - If the portion size is given in household measures (e.g., "1 scoop"), try to find the corresponding gram/milliliter weight usually listed in parentheses (e.g., "30g"). Use the weight as priority.
        - Use Title Case for product_name when a name is present.
        """

        let prompt = """
        nutrition_table_image (OCR text):
        \(text)

        Return JSON with keys:
        productName, portionUnit, portionSize, calories, proteinG, carbohydratesG, totalFatG.
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: prompt, generating: NutritionLabelDraft.self)
        return response.content
    }

    private func parseWithRemoteModel(image: UIImage, integration: AIIntegrationRecord) async throws -> RemoteParseResult {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw ScanError.invalidImage
        }
        let base64 = imageData.base64EncodedString()

        switch integration.provider {
        case .openai:
            return try await parseWithOpenAI(base64: base64, apiKey: integration.apiKey)
        case .anthropic:
            return try await parseWithAnthropic(base64: base64, apiKey: integration.apiKey)
        }
    }

    private func parseWithOpenAI(base64: String, apiKey: String) async throws -> RemoteParseResult {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Objective

        Extract nutritional information from the provided image of a nutrition facts label. Identify the product name (if visible), serving size information, calories, and specific macronutrients per serving.

        Instructions
        1. Analyze the image provided in nutrition_table_image.
        2. Extract the following information:
        - Product Name: Look for the name of the ingredient or product. If not explicitly present in the image, return "-".
        - Calories: Total energy/calories per serving.
        - Portion Size: The numeric value of the serving size (e.g., 30).
        - Portion Unit: The unit of measurement for the serving size (e.g., g, ml, tbsp).
        - Macronutrients: Extract the values (in grams) per portion for Protein, Total Carbohydrates, and Total Fat.
        3. Output JSON only (no markdown fences, no explanation) using the schema below.

        Observations
        - Ensure all macronutrient values are strictly numbers representing grams. If a value is missing or zero, treat it as 0 unless specified otherwise.
        - If the portion size is given in household measures (e.g., "1 scoop"), try to find the corresponding gram/milliliter weight usually listed in parentheses (e.g., "30g"). Use the weight as priority.
        - Use Title Case for product_name when a name is present.
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "product_name": [
                    "type": "string",
                    "description": "Name of the product or ingredient found in the image, or \"-\" if not found."
                ],
                "calories": [
                    "type": "number",
                    "description": "Total calories per serving."
                ],
                "portion_size": [
                    "type": "number",
                    "description": "Numeric value of the serving size."
                ],
                "portion_unit": [
                    "type": "string",
                    "description": "Unit of measurement for the serving size (e.g., \"g\", \"ml\")."
                ],
                "macros_per_portion": [
                    "type": "object",
                    "description": "Object containing macronutrients in grams.",
                    "properties": [
                        "protein_g": [
                            "type": "number",
                            "description": "Amount of protein in grams per serving."
                        ],
                        "carbohydrates_g": [
                            "type": "number",
                            "description": "Amount of total carbohydrates in grams per serving."
                        ],
                        "total_fat_g": [
                            "type": "number",
                            "description": "Amount of total fat in grams per serving."
                        ]
                    ],
                    "required": ["protein_g", "carbohydrates_g", "total_fat_g"],
                    "additionalProperties": false
                ]
            ],
            "required": ["product_name", "calories", "portion_size", "portion_unit", "macros_per_portion"],
            "additionalProperties": false
        ]

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "max_output_tokens": 600,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt],
                        ["type": "input_image", "image_url": "data:image/jpeg;base64,\(base64)"]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "nutrition_label",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        struct OpenAIResponse: Decodable {
            struct OutputItem: Decodable {
                struct ContentItem: Decodable {
                    let type: String
                    let text: String?
                }

                let type: String
                let content: [ContentItem]?
            }

            let output: [OutputItem]?
            let outputText: String?

            private enum CodingKeys: String, CodingKey {
                case output
                case outputText = "output_text"
            }
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let outputText = decoded.outputText {
            let draft = try decodeOpenAIOutput(outputText)
            return RemoteParseResult(draft: draft, rawText: outputText)
        }

        let contentText = decoded.output?
            .compactMap { $0.content?.first(where: { $0.type == "output_text" || $0.type == "text" })?.text }
            .first

        guard let contentText else {
            throw ScanError.remoteParseFailed("No text content in OpenAI response.")
        }

        let draft = try decodeOpenAIOutput(contentText)
        return RemoteParseResult(draft: draft, rawText: contentText)
    }

    private func parseWithAnthropic(base64: String, apiKey: String) async throws -> RemoteParseResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let prompt = """
        Objective

        Extract nutritional information from the provided image of a nutrition facts label. Identify the product name (if visible), serving size information, calories, and specific macronutrients per serving.

        Instructions
        1. Analyze the image provided in nutrition_table_image.
        2. Extract the following information:
        - Product Name: Look for the name of the ingredient or product. If not explicitly present in the image, return "-".
        - Calories: Total energy/calories per serving.
        - Portion Size: The numeric value of the serving size (e.g., 30).
        - Portion Unit: The unit of measurement for the serving size (e.g., g, ml, tbsp).
        - Macronutrients: Extract the values (in grams) per portion for Protein, Total Carbohydrates, and Total Fat.
        3. Output JSON only (no markdown fences, no explanation) using the schema below.

        Observations
        - Ensure all macronutrient values are strictly numbers representing grams. If a value is missing or zero, treat it as 0 unless specified otherwise.
        - If the portion size is given in household measures (e.g., "1 scoop"), try to find the corresponding gram/milliliter weight usually listed in parentheses (e.g., "30g"). Use the weight as priority.
        - Use Title Case for product_name when a name is present.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 800,
            "messages": [
                ["role": "user", "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                    ["type": "text", "text": prompt]
                ]]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        struct AnthropicResponse: Decodable {
            struct ContentBlock: Decodable { let type: String; let text: String? }
            let content: [ContentBlock]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw ScanError.remoteParseFailed("No text content in Anthropic response.")
        }

        let draft = try decodeNutritionJSON(text)
        return RemoteParseResult(draft: draft, rawText: text)
    }

    private func encodeDraftJSON(_ draft: NutritionLabelDraft) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeOpenAIOutput(_ text: String) throws -> NutritionLabelDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ScanError.remoteParseFailed("OpenAI response was not valid UTF-8.")
        }

        let output = try JSONDecoder().decode(OpenAILabelOutput.self, from: data)
        return NutritionLabelDraft(
            productName: output.productName,
            portionUnit: output.portionUnit,
            portionSize: output.portionSize,
            calories: output.calories,
            proteinG: output.macros.proteinG,
            carbohydratesG: output.macros.carbohydratesG,
            totalFatG: output.macros.totalFatG
        )
    }

    private func decodeNutritionJSON(_ text: String) throws -> NutritionLabelDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(NutritionLabelDraft.self, from: data) {
            return decoded
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw ScanError.remoteParseFailed("No JSON object found in model output.")
        }

        let substring = String(trimmed[start...end])
        let data = Data(substring.utf8)
        do {
            return try JSONDecoder().decode(NutritionLabelDraft.self, from: data)
        } catch {
            let preview = String(substring.prefix(400))
            throw ScanError.remoteParseFailed("Failed to decode JSON. Output preview: \(preview)")
        }
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ScanError.remoteRequestFailed(statusCode: http.statusCode, body: body)
        }
    }

    enum ScanError: LocalizedError {
        case invalidImage
        case modelUnavailable
        case remoteRequestFailed(statusCode: Int, body: String)
        case remoteParseFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "No se pudo leer la imagen."
            case .modelUnavailable:
                return "Apple Intelligence no esta disponible o no esta activado."
            case .remoteRequestFailed(let statusCode, let body):
                return "Remote request failed (HTTP \(statusCode)). Response: \(body)"
            case .remoteParseFailed(let details):
                return "Failed to interpret model response. \(details)"
            }
        }
    }
}
