import Foundation

struct AIProviderCreditService {
    struct Result {
        let displayText: String
    }

    enum ServiceError: LocalizedError {
        case invalidResponse
        case missingAPIKey
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from provider."
            case .missingAPIKey:
                return "Enter an API key first."
            case .requestFailed(let message):
                return message
            }
        }
    }

    func verifyAndFetchCredit(provider: AIProvider, apiKey: String) async throws -> Result {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServiceError.missingAPIKey
        }

        switch provider {
        case .openai:
            try await validateOpenAIKey(apiKey: trimmed)
            return Result(displayText: "\(provider.displayName) key confirmed.")
        case .anthropic:
            try await validateAnthropicKey(apiKey: trimmed)
            return Result(displayText: "\(provider.displayName) key confirmed.")
        }
    }

    private func validateOpenAIKey(apiKey: String) async throws {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await perform(request, provider: .openai)
        try validateHTTP(response, data: data, provider: .openai)
    }

    private func validateAnthropicKey(apiKey: String) async throws {
        let url = URL(string: "https://api.anthropic.com/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await perform(request, provider: .anthropic)
        try validateHTTP(response, data: data, provider: .anthropic)
    }

    private func perform(_ request: URLRequest, provider: AIProvider) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw ServiceError.requestFailed("No internet connection. Check your network and try again.")
            case .timedOut:
                throw ServiceError.requestFailed("Request to \(provider.displayName) timed out. Try again.")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw ServiceError.requestFailed("Could not reach \(provider.displayName). Try again in a moment.")
            default:
                throw ServiceError.requestFailed("Network error while contacting \(provider.displayName).")
            }
        } catch {
            throw ServiceError.requestFailed("Could not reach \(provider.displayName) right now.")
        }
    }

    private func validateHTTP(_ response: URLResponse, data: Data, provider: AIProvider) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let providerMessage = sanitizedProviderMessage(extractErrorMessage(from: data))
            throw ServiceError.requestFailed(
                userFriendlyMessage(
                    statusCode: http.statusCode,
                    provider: provider,
                    providerMessage: providerMessage
                )
            )
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let type = error["type"] as? String, !type.isEmpty {
                return type
            }
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }

    private func userFriendlyMessage(
        statusCode: Int,
        provider: AIProvider,
        providerMessage: String?
    ) -> String {
        switch statusCode {
        case 401:
            return "The API key was rejected by \(provider.displayName). Check the key and try again."
        case 403:
            return "This API key does not have permission for this \(provider.displayName) request."
        case 429:
            return "\(provider.displayName) is rate limiting requests right now. Wait a moment and try again."
        case 500 ... 599:
            return "\(provider.displayName) is currently unavailable. Try again shortly."
        default:
            if let providerMessage, !providerMessage.isEmpty {
                return "\(provider.displayName) error (\(statusCode)): \(providerMessage)"
            }
            return "Request to \(provider.displayName) failed with HTTP \(statusCode)."
        }
    }

    private func sanitizedProviderMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let singleLine = trimmed
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let collapsed = singleLine.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return String(collapsed.prefix(180))
    }

}

private extension AIProvider {
    var displayName: String {
        rawValue.capitalized
    }
}
