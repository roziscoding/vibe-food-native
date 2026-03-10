import Foundation
import FoundationModels

@Generable(description: "Structured nutrition insights for today")
struct InsightContent: Codable {
    @Guide(description: "Opening summary paragraph analyzing yesterday's nutrition")
    var summary: String

    @Guide(description: "Short practical bullets for today")
    var bullets: [String]
}

@Generable(description: "Very short coaching message about a day's logged meals")
struct TodaySoFarContent: Codable {
    @Guide(description: "One short encouraging message with a practical nudge for the rest of the day")
    var message: String
}

struct InsightInputBuilder {
    private let summaryService = DailySummaryService()

    func fetchGoals(settingsRepository: SettingsRepository) throws -> MacroTargets {
        if let settings = try settingsRepository.fetchSettings() {
            return MacroTargets(
                calories: settings.calorieGoal,
                protein: settings.proteinGoal,
                carbs: settings.carbsGoal,
                fat: settings.fatGoal
            )
        }

        return MacroTargets(calories: 2000, protein: 150, carbs: 250, fat: 70)
    }

    func fetchProfile(settingsRepository: SettingsRepository) throws -> InsightGenerationInput.ProfilePayload? {
        guard let settings = try settingsRepository.fetchSettings(),
              let age = settings.age,
              let heightCm = settings.heightCm,
              let weightKg = settings.weightKg,
              let sex = settings.sex,
              let activityLevel = settings.activityLevel,
              let objective = settings.objective else {
            return nil
        }

        return InsightGenerationInput.ProfilePayload(
            age: age,
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sex.rawValue,
            activityLevel: activityLevel.rawValue,
            objective: objective.rawValue
        )
    }

    func makeInput(
        targetDay: String,
        sourceDay: String,
        meals: [MealRecord],
        goals: MacroTargets,
        profile: InsightGenerationInput.ProfilePayload?
    ) -> InsightGenerationInput {
        let summary = summaryService.summary(for: meals, goals: goals)

        return InsightGenerationInput(
            targetDay: targetDay,
            sourceDay: sourceDay,
            profile: profile,
            goals: .init(
                calories: goals.calories,
                protein: goals.protein,
                carbs: goals.carbs,
                fat: goals.fat
            ),
            previousDayTotals: .init(
                calories: summary.totals.calories,
                protein: summary.totals.protein,
                carbs: summary.totals.carbs,
                fat: summary.totals.fat
            ),
            previousDayMeals: meals.map {
                InsightGenerationInput.MealPayload(
                    name: $0.name,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    time: AppFormatters.shortTime.string(from: $0.consumedAt)
                )
            }
        )
    }
}

struct InsightGenerationInput: Encodable {
    struct ProfilePayload: Encodable {
        let age: Int
        let heightCm: Double
        let weightKg: Double
        let sex: String
        let activityLevel: String
        let objective: String
    }

    struct GoalPayload: Encodable {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    struct MealPayload: Encodable {
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let time: String
    }

    struct MacroPayload: Encodable {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    let targetDay: String
    let sourceDay: String
    let profile: ProfilePayload?
    let goals: GoalPayload
    let previousDayTotals: MacroPayload
    let previousDayMeals: [MealPayload]
}

struct InsightsService {
    struct InsightResult {
        let content: String
        let providerLabel: String
    }

    func generateInsights(
        input: InsightGenerationInput,
        integration: AIIntegrationRecord?
    ) async throws -> InsightResult {
        if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch integration.provider {
            case .openai:
                let content = try await generateWithOpenAI(input: input, apiKey: integration.apiKey)
                return InsightResult(content: content, providerLabel: "OpenAI")
            case .anthropic:
                let content = try await generateWithAnthropic(input: input, apiKey: integration.apiKey)
                return InsightResult(content: content, providerLabel: "Anthropic")
            }
        }

        let content = try await generateWithLocalModel(input: input)
        return InsightResult(content: content, providerLabel: "Local model")
    }

    func generateTodaySoFarMessage(
        input: InsightGenerationInput,
        integration: AIIntegrationRecord?
    ) async throws -> InsightResult {
        if let integration, !integration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch integration.provider {
            case .openai:
                let content = try await generateTodaySoFarWithOpenAI(input: input, apiKey: integration.apiKey)
                return InsightResult(content: content, providerLabel: "OpenAI")
            case .anthropic:
                let content = try await generateTodaySoFarWithAnthropic(input: input, apiKey: integration.apiKey)
                return InsightResult(content: content, providerLabel: "Anthropic")
            }
        }

        let content = fallbackTodaySoFarMessage(input: input)
        return InsightResult(content: content, providerLabel: "Built-in guidance")
    }

    private func generateWithLocalModel(input: InsightGenerationInput) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw InsightError.modelUnavailable
        }

        let prompt = try promptText(for: input)
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(to: prompt, generating: InsightContent.self)
        return try encodeInsightContent(response.content)
    }

    private func generateWithOpenAI(input: InsightGenerationInput, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "max_output_tokens": 800,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": try promptText(for: input)
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "insight_content",
                    "strict": true,
                    "schema": Self.openAISchema
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
        if let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !outputText.isEmpty {
            let content = try decodeInsightContent(outputText)
            return try encodeInsightContent(content)
        }

        let text = decoded.output?
            .compactMap { $0.content?.first(where: { $0.type == "output_text" || $0.type == "text" })?.text }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw InsightError.remoteParseFailed("No text content in OpenAI response.")
        }

        let content = try decodeInsightContent(text)
        return try encodeInsightContent(content)
    }

    private func generateTodaySoFarWithOpenAI(input: InsightGenerationInput, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "max_output_tokens": 220,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": try promptText(for: input, instructions: Self.todaySoFarInstructions)
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "today_so_far_content",
                    "strict": true,
                    "schema": Self.todaySoFarOpenAISchema
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
        if let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !outputText.isEmpty {
            let content = try decodeTodaySoFarContent(outputText)
            return sanitizeTodaySoFarMessage(content.message)
        }

        let text = decoded.output?
            .compactMap { $0.content?.first(where: { $0.type == "output_text" || $0.type == "text" })?.text }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw InsightError.remoteParseFailed("No text content in OpenAI response.")
        }

        let content = try decodeTodaySoFarContent(text)
        return sanitizeTodaySoFarMessage(content.message)
    }

    private func generateWithAnthropic(input: InsightGenerationInput, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 900,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": try promptText(for: input)
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        struct AnthropicResponse: Decodable {
            struct ContentBlock: Decodable {
                let type: String
                let text: String?
            }

            let content: [ContentBlock]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw InsightError.remoteParseFailed("No text content in Anthropic response.")
        }

        let content = try decodeInsightContent(text)
        return try encodeInsightContent(content)
    }

    private func generateTodaySoFarWithAnthropic(input: InsightGenerationInput, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 260,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": try promptText(for: input, instructions: Self.todaySoFarInstructions)
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        struct AnthropicResponse: Decodable {
            struct ContentBlock: Decodable {
                let type: String
                let text: String?
            }

            let content: [ContentBlock]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw InsightError.remoteParseFailed("No text content in Anthropic response.")
        }

        let content = try decodeTodaySoFarContent(text)
        return sanitizeTodaySoFarMessage(content.message)
    }

    private func encodeInsightContent(_ content: InsightContent) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(content)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func decodeInsightContent(_ text: String) throws -> InsightContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(InsightContent.self, from: data) {
            return decoded
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw InsightError.remoteParseFailed("No JSON object found in insight response.")
        }

        let substring = String(trimmed[start...end])
        let data = Data(substring.utf8)
        do {
            return try JSONDecoder().decode(InsightContent.self, from: data)
        } catch {
            let preview = String(substring.prefix(400))
            throw InsightError.remoteParseFailed("Failed to decode insight JSON. Output preview: \(preview)")
        }
    }

    private func decodeTodaySoFarContent(_ text: String) throws -> TodaySoFarContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(TodaySoFarContent.self, from: data) {
            return decoded
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw InsightError.remoteParseFailed("No JSON object found in today-so-far response.")
        }

        let substring = String(trimmed[start...end])
        let data = Data(substring.utf8)
        do {
            return try JSONDecoder().decode(TodaySoFarContent.self, from: data)
        } catch {
            let preview = String(substring.prefix(240))
            throw InsightError.remoteParseFailed("Failed to decode today-so-far JSON. Output preview: \(preview)")
        }
    }

    private func sanitizeTodaySoFarMessage(_ message: String) -> String {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func fallbackTodaySoFarMessage(input: InsightGenerationInput) -> String {
        let meals = input.previousDayMeals
        let totals = input.previousDayTotals
        let goals = input.goals
        let calorieProgress = progress(totals.calories, toward: goals.calories)
        let proteinProgress = progress(totals.protein, toward: goals.protein)
        let carbProgress = progress(totals.carbs, toward: goals.carbs)
        let fatProgress = progress(totals.fat, toward: goals.fat)
        let objective = input.profile.flatMap { GoalObjective(rawValue: $0.objective) }

        if meals.isEmpty {
            return "No meals logged yet; start with a protein-rich meal and something fresh to set the day up well."
        }

        if carbProgress > 0.75 && proteinProgress < 0.5 {
            return "Carbs are leading so far; steer the next meal toward lean protein and something fresh."
        }

        if fatProgress > 0.7 && proteinProgress < 0.6 {
            return "Meals look satisfying so far; keep the next one lighter and anchor it with lean protein."
        }

        if proteinProgress < 0.35 && calorieProgress >= 0.45 {
            switch objective {
            case .loseWeight:
                return "Energy is coming in; keep the next meal lighter and more protein-forward to stay in control."
            case .gainWeight, .muscle:
                return "Calories are moving; push the next meal harder on protein to support your goal."
            case .maintainWeight, nil:
                return "Energy is coming in; make the next meal more protein-forward to keep things balanced."
            }
        }

        switch objective {
        case .gainWeight, .muscle:
            if calorieProgress < 0.5 {
                return "Light start for your goal; make the next meal bigger, protein-heavy, and include some carbs."
            }
        case .loseWeight:
            if calorieProgress > 0.75 {
                return "You’ve eaten a fair amount already; keep the next meal filling with protein and vegetables."
            }
        case .maintainWeight, nil:
            break
        }

        if proteinProgress >= 0.6 && calorieProgress <= 0.7 {
            return "Protein is tracking well; keep the next meal balanced and add produce if it’s missing."
        }

        if calorieProgress < 0.35 {
            return "Light start so far; make the next meal substantial with protein, carbs, and something fresh."
        }

        return "Good start so far; keep the next meal balanced and prioritize protein to stay on track."
    }

    private func progress(_ value: Double, toward goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return value / goal
    }

    private func promptText(for input: InsightGenerationInput) throws -> String {
        try promptText(for: input, instructions: Self.instructions)
    }

    private func promptText(for input: InsightGenerationInput, instructions: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(input)
        let payload = String(data: data, encoding: .utf8) ?? "{}"

        return """
        \(instructions)

        input:
        \(payload)
        """
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw InsightError.remoteRequestFailed(statusCode: http.statusCode, body: body)
        }
    }

    private static let instructions = """
    You are generating daily nutrition insights for today based on the user's goals, body profile, objective, and yesterday's food intake.

    Requirements:
    - Return structured output with two fields: summary and bullets.
    - The summary must be a short opening paragraph that summarizes and analyzes yesterday's nutrition.
    - Bullets must contain 3 to 5 short practical bullets for today.
    - Mention what went well yesterday, what seems off relative to goals, and one or two practical suggestions for today.
    - If body profile and objective are available, use them to tailor the advice.
    - Use the same language implied by the meal names when possible. Default to English if unclear.
    - Do not invent meals or macros that are not present in the input.
    - Keep the tone direct and practical.
    - Do not include a title, headline label, date label, or section header like "Daily nutrition insights for...".
    - The summary is not a title. It should read like a natural first paragraph.
    """

    private static let todaySoFarInstructions = """
    You are generating a very short nutrition coaching message about the user's meals for the selected day.

    Requirements:
    - Return structured output with one field: message.
    - The message must be exactly one short sentence and no more than 24 words.
    - Keep the tone encouraging, specific, and slightly corrective when needed.
    - Mention what looks good so far and give one practical nudge grounded in that day's meals.
    - If the user has not logged any meals yet, encourage a strong first meal with protein and reasonable balance.
    - If body profile and objective are available, use them to tailor the nudge.
    - Use the same language implied by the meal names when possible. Default to English if unclear.
    - Do not invent meals or macros that are not present in the input.
    - Do not include bullets, emojis, quotation marks, labels, or a title.
    """


    private static let openAISchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "Opening summary paragraph analyzing yesterday's nutrition."
            ],
            "bullets": [
                "type": "array",
                "description": "Three to five short practical bullets for today.",
                "items": [
                    "type": "string"
                ]
            ]
        ],
        "required": ["summary", "bullets"],
        "additionalProperties": false
    ]

    private static let todaySoFarOpenAISchema: [String: Any] = [
        "type": "object",
        "properties": [
            "message": [
                "type": "string",
                "description": "One very short encouraging message about the selected day's meals."
            ]
        ],
        "required": ["message"],
        "additionalProperties": false
    ]

    enum InsightError: LocalizedError {
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
                return "Failed to interpret insight response. \(details)"
            }
        }
    }
}
