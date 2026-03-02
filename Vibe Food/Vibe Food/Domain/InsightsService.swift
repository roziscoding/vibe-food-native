import Foundation
import FoundationModels

@Generable(description: "Structured nutrition insights for today")
struct InsightContent: Codable {
    @Guide(description: "Opening summary paragraph analyzing yesterday's nutrition")
    var summary: String

    @Guide(description: "Short practical bullets for today")
    var bullets: [String]
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

    private func promptText(for input: InsightGenerationInput) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(input)
        let payload = String(data: data, encoding: .utf8) ?? "{}"

        return """
        \(Self.instructions)

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
