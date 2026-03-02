import Foundation
import FoundationModels

@Generable(description: "Resultado del analisis de una descripcion de comida")
struct MealAILogDraft: Codable {
    @Guide(description: "Nombre final de la comida")
    var mealName: String

    @Guide(description: "Ingredientes detectados de la lista disponible")
    var matchedIngredients: [MealAILogDraftMatchedIngredient]

    @Guide(description: "Ingredientes nuevos no encontrados en la lista")
    var newIngredients: [MealAILogDraftNewIngredient]
}

@Generable(description: "Ingrediente detectado y vinculado a la lista disponible")
struct MealAILogDraftMatchedIngredient: Codable {
    @Guide(description: "Identificador del ingrediente disponible")
    var ingredientId: String

    @Guide(description: "Cantidad del ingrediente en la unidad del ingrediente")
    var amount: Double
}

@Generable(description: "Ingrediente nuevo que no existe en la lista disponible")
struct MealAILogDraftNewIngredient: Codable {
    @Guide(description: "Nombre del nuevo ingrediente")
    var name: String

    @Guide(description: "Unidad del nuevo ingrediente")
    var unit: String

    @Guide(description: "Tamano de porcion en la misma unidad")
    var portionSize: Double

    @Guide(description: "Calorias por porcion")
    var calories: Double

    @Guide(description: "Carbohidratos por porcion")
    var carbs: Double

    @Guide(description: "Proteinas por porcion")
    var proteins: Double

    @Guide(description: "Grasas por porcion")
    var fat: Double
}

struct MealAILogPayload: Decodable {
    struct MatchedIngredient: Decodable {
        let ingredientId: UUID
        let amount: Double

        enum CodingKeys: String, CodingKey {
            case ingredientId = "ingredient_id"
            case amount
        }

        init(ingredientId: UUID, amount: Double) {
            self.ingredientId = ingredientId
            self.amount = amount
        }
    }

    struct NewIngredient: Decodable {
        let name: String
        let unit: String
        let portionSize: Double
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double

        enum CodingKeys: String, CodingKey {
            case name
            case unit
            case portionSize = "portion_size"
            case calories
            case protein
            case proteins
            case carbs
            case fat
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            unit = try container.decode(String.self, forKey: .unit)
            portionSize = try container.decode(Double.self, forKey: .portionSize)
            calories = try container.decode(Double.self, forKey: .calories)
            if let proteinValue = try container.decodeIfPresent(Double.self, forKey: .protein) {
                protein = proteinValue
            } else if let proteinsValue = try container.decodeIfPresent(Double.self, forKey: .proteins) {
                protein = proteinsValue
            } else {
                protein = 0
            }
            carbs = try container.decode(Double.self, forKey: .carbs)
            fat = try container.decode(Double.self, forKey: .fat)
        }

        init(
            name: String,
            unit: String,
            portionSize: Double,
            calories: Double,
            protein: Double,
            carbs: Double,
            fat: Double
        ) {
            self.name = name
            self.unit = unit
            self.portionSize = portionSize
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }
    }

    let mealName: String
    let matchedIngredients: [MatchedIngredient]
    let newIngredients: [NewIngredient]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case matchedIngredients = "matched_ingredients"
        case newIngredients = "new_ingredients"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mealName = try container.decode(String.self, forKey: .mealName)
        matchedIngredients = try container.decodeIfPresent([MatchedIngredient].self, forKey: .matchedIngredients) ?? []
        newIngredients = try container.decodeIfPresent([NewIngredient].self, forKey: .newIngredients) ?? []
    }

    init(mealName: String, matchedIngredients: [MatchedIngredient], newIngredients: [NewIngredient]) {
        self.mealName = mealName
        self.matchedIngredients = matchedIngredients
        self.newIngredients = newIngredients
    }
}

struct MealAILogInput: Encodable {
    let mealName: String?
    let mealDescription: String
    let availableIngredientsList: [AvailableIngredient]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case mealDescription = "meal_description"
        case availableIngredientsList = "available_ingredients_list"
    }
}

struct AvailableIngredient: Encodable {
    let ingredientId: String
    let name: String
    let unit: String
    let kcalPerUnit: Double
    let proteinPerUnitG: Double
    let carbsPerUnitG: Double
    let fatPerUnitG: Double

    enum CodingKeys: String, CodingKey {
        case ingredientId = "ingredient_id"
        case name
        case unit
        case kcalPerUnit = "kcal_per_unit"
        case proteinPerUnitG = "protein_per_unit_g"
        case carbsPerUnitG = "carbs_per_unit_g"
        case fatPerUnitG = "fat_per_unit_g"
    }
}

struct MealAILogService {
    struct LogResult {
        let payload: MealAILogPayload
        let rawText: String?
    }

    func logMeal(
        mealName: String?,
        description: String,
        availableIngredients: [AvailableIngredient],
        integration: AIIntegrationRecord?
    ) async throws -> LogResult {
        let input = MealAILogInput(
            mealName: mealName?.isEmpty == true ? nil : mealName,
            mealDescription: description,
            availableIngredientsList: availableIngredients
        )

        if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch integration.provider {
            case .openai:
                return try await logWithOpenAI(input: input, apiKey: integration.apiKey)
            case .anthropic:
                return try await logWithAnthropic(input: input, apiKey: integration.apiKey)
            }
        }

        return try await logWithLocalModel(input: input)
    }

    private func logWithLocalModel(input: MealAILogInput) async throws -> LogResult {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw MealAIError.modelUnavailable
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let inputData = try encoder.encode(input)
        let inputJSON = String(data: inputData, encoding: .utf8) ?? ""

        let instructions = MealAILogService.prompt
        let prompt = """
        inputs:
        \(inputJSON)
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: prompt, generating: MealAILogDraft.self)
        let draft = response.content

        let payload = MealAILogPayload(
            mealName: draft.mealName,
            matchedIngredients: draft.matchedIngredients.compactMap { item in
                guard let uuid = UUID(uuidString: item.ingredientId) else { return nil }
                return MealAILogPayload.MatchedIngredient(ingredientId: uuid, amount: item.amount)
            },
            newIngredients: draft.newIngredients.map {
                MealAILogPayload.NewIngredient(
                    name: $0.name,
                    unit: $0.unit,
                    portionSize: $0.portionSize,
                    calories: $0.calories,
                    protein: $0.proteins,
                    carbs: $0.carbs,
                    fat: $0.fat
                )
            }
        )

        let outputText = encodeDraftJSON(draft)
        return LogResult(payload: payload, rawText: outputText)
    }

    private func logWithOpenAI(input: MealAILogInput, apiKey: String) async throws -> LogResult {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let inputData = try encoder.encode(input)
        let inputJSON = String(data: inputData, encoding: .utf8) ?? ""

        let prompt = """
        \(MealAILogService.prompt)

        inputs:
        \(inputJSON)
        """

        let schema = MealAILogService.openAISchema

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "max_output_tokens": 1200,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "meal_log",
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
        let contentText = decoded.outputText
            ?? decoded.output?
                .compactMap { $0.content?.first(where: { $0.type == "output_text" || $0.type == "text" })?.text }
                .first

        guard let contentText else {
            throw MealAIError.remoteParseFailed("No text content in OpenAI response.")
        }

        let payload = try decodeMealAIJSON(contentText)
        return LogResult(payload: payload, rawText: contentText)
    }

    private func logWithAnthropic(input: MealAILogInput, apiKey: String) async throws -> LogResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let inputData = try encoder.encode(input)
        let inputJSON = String(data: inputData, encoding: .utf8) ?? ""

        let prompt = """
        \(MealAILogService.prompt)

        inputs:
        \(inputJSON)
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1400,
            "messages": [
                ["role": "user", "content": [
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
            throw MealAIError.remoteParseFailed("No text content in Anthropic response.")
        }

        let payload = try decodeMealAIJSON(text)
        return LogResult(payload: payload, rawText: text)
    }

    private func encodeDraftJSON(_ draft: MealAILogDraft) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeMealAIJSON(_ text: String) throws -> MealAILogPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(MealAILogPayload.self, from: data) {
            return decoded
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw MealAIError.remoteParseFailed("No JSON object found in model output.")
        }

        let substring = String(trimmed[start...end])
        let data = Data(substring.utf8)
        do {
            return try JSONDecoder().decode(MealAILogPayload.self, from: data)
        } catch {
            let preview = String(substring.prefix(400))
            throw MealAIError.remoteParseFailed("Failed to decode JSON. Output preview: \(preview)")
        }
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw MealAIError.remoteRequestFailed(statusCode: http.statusCode, body: body)
        }
    }

    private static let prompt = """
    Objective

    Your task is to analyze a meal description containing ingredients and amounts, and match them against a provided list of available ingredients. For each matched item, return the specific ingredient_id from the available list and the quantity specified in the meal description.

    Instructions
    1. Read the text provided in meal_description to identify the ingredients used and their respective quantities.
    2. Review the list of ingredients in available_ingredients_list. Each item has a unique ingredient_id, unit, and per-unit nutrition values.
    3. If meal_name is provided and non-empty, copy it exactly into the output field meal_name. If it is missing or empty, generate a concise descriptive meal_name in the same language as the ingredient list/description.
    4. Match the ingredients found in the meal description to the most appropriate item in the available ingredients list based on semantic similarity.
    5. Extract the amount associated with that ingredient from the meal description.
    6. When the unit in the meal description does not match the unit in the available ingredient, convert the amount to the available ingredient unit and output the converted amount.
    7. Output JSON only (no markdown fences, no explanation) using the schema below.

    Observations
    - If an ingredient in the meal description cannot be confidently matched to the available list, add it to new_ingredients instead of guessing.
    - For new_ingredients, estimate nutrition values (calories, carbs, proteins, fat) as accurately as possible using common nutrition knowledge.
    - New ingredient names must match the language used by the existing ingredient list.
    - Use Title Case for meal_name and new_ingredients names (while keeping the same language).
    - Use non-negative numbers only.
    - If no new ingredients are needed, you may omit new_ingredients or return an empty array.
    - Always include a non-empty meal_name in the output JSON.
    - Keep meal_name short and natural. Do not list all ingredients in the name (e.g. prefer "Egg sandwich" instead of "Egg sandwich with mayo, cheese, and ham").

    Output schema
    {
      "meal_name": {
        "type": "string",
        "description": "Final meal name. If meal_name was provided in the input, copy it exactly. Otherwise, suggest a concise descriptive meal name in the same language as the ingredient list/description."
      },
      "matched_ingredients": {
        "type": "array",
        "description": "List of ingredients matched between the meal description and available inventory",
        "items": {
          "type": "object",
          "properties": {
            "ingredient_id": {
              "type": "string",
              "description": "The unique identifier of the ingredient from the available list"
            },
            "amount": {
              "type": "number",
              "description": "The quantity of the ingredient, converted to the matched ingredient unit when needed"
            }
          }
        }
      },
      "new_ingredients": {
        "type": "array",
        "optional": false,
        "items": {
          "type": "object",
          "properties": {
            "name": {
              "type": "string",
              "description": "Name of the new ingredient"
            },
            "unit": {
              "type": "string",
              "description": "Unit of measure for the new ingredient"
            },
            "portion_size": {
              "type": "number",
              "description": "Portion size in the same unit used in the unit field"
            },
            "calories": {
              "type": "number",
              "description": "Calories per portion in kcal"
            },
            "carbs": {
              "type": "number",
              "description": "Carbs per portion in grams"
            },
            "proteins": {
              "type": "number",
              "description": "Protein per portion in grams"
            },
            "fat": {
              "type": "number",
              "description": "Fat per portion in grams"
            }
          }
        }
      }
    }

    inputs:

    {
      "meal_name": "<provided meal name or null>",
      "meal_description": "<user description>",
      "available_ingredients_list": [
        {
          "ingredient_id": "<uuid>",
          "name": "<ingredient name>",
          "unit": "<unit>",
          "kcal_per_unit": 0,
          "protein_per_unit_g": 0,
          "carbs_per_unit_g": 0,
          "fat_per_unit_g": 0
        }
      ]
    }
    """

    private static let openAISchema: [String: Any] = [
        "type": "object",
        "properties": [
            "meal_name": [
                "type": "string",
                "description": "Final meal name. If meal_name was provided in the input, copy it exactly. Otherwise, suggest a concise descriptive meal name in the same language as the ingredient list/description."
            ],
            "matched_ingredients": [
                "type": "array",
                "description": "List of ingredients matched between the meal description and available inventory",
                "items": [
                    "type": "object",
                    "properties": [
                        "ingredient_id": [
                            "type": "string",
                            "description": "The unique identifier of the ingredient from the available list"
                        ],
                        "amount": [
                            "type": "number",
                            "description": "The quantity of the ingredient, converted to the matched ingredient unit when needed"
                        ]
                    ],
                    "required": ["ingredient_id", "amount"],
                    "additionalProperties": false
                ]
            ],
            "new_ingredients": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "unit": ["type": "string"],
                        "portion_size": ["type": "number"],
                        "calories": ["type": "number"],
                        "carbs": ["type": "number"],
                        "proteins": ["type": "number"],
                        "fat": ["type": "number"]
                    ],
                    "required": [
                        "name",
                        "unit",
                        "portion_size",
                        "calories",
                        "carbs",
                        "proteins",
                        "fat"
                    ],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["meal_name", "matched_ingredients", "new_ingredients"],
        "additionalProperties": false
    ]

    enum MealAIError: LocalizedError {
        case modelUnavailable
        case remoteRequestFailed(statusCode: Int, body: String)
        case remoteParseFailed(String)

        var errorDescription: String? {
            switch self {
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
