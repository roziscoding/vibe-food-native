import Foundation
import UIKit

enum ErrorReportKey {
    static let dashboardAlert = "dashboard.alert"
    static let foodAlert = "food.alert"
    static let inputAlert = "input.alert"
    static let waterAlert = "water.alert"
    static let settingsAlert = "settings.alert"
    static let settingsAICredit = "settings.ai-credit"
    static let ingredientsAlert = "ingredients.alert"
    static let ingredientsScan = "ingredients.scan"
    static let mealsAlert = "meals.alert"
    static let mealsDraft = "meals.draft"
    static let mealsAILog = "meals.ai-log"
    static let mealsTodaySoFar = "meals.today-so-far"
    static let insightsStatus = "insights.status"
}

struct ErrorReportContext: Sendable {
    let capturedAt: Date
    let feature: String
    let operation: String
    let userMessage: String
    let detailedLog: String
    let llmInput: String?
    let llmOutput: String?
    let llmProvider: String?
    let llmModel: String?
}

actor ErrorReportStore {
    static let shared = ErrorReportStore()
    private var latestByKey: [String: ErrorReportContext] = [:]

    func record(_ context: ErrorReportContext, for key: String) {
        latestByKey[key] = context
    }

    func latest(for key: String) -> ErrorReportContext? {
        latestByKey[key]
    }
}

enum ErrorReportService {
    static func capture(
        key: String,
        feature: String,
        operation: String,
        userMessage: String,
        error: Error? = nil,
        detailLog: String? = nil,
        llmInput: String? = nil,
        llmOutput: String? = nil,
        llmProvider: String? = nil,
        llmModel: String? = nil
    ) {
        let context = ErrorReportContext(
            capturedAt: Date(),
            feature: feature,
            operation: operation,
            userMessage: userMessage,
            detailedLog: detailLog ?? detailedLog(for: error),
            llmInput: llmInput,
            llmOutput: llmOutput,
            llmProvider: llmProvider,
            llmModel: llmModel
        )

        Task {
            await ErrorReportStore.shared.record(context, for: key)
        }
    }

    static func makePayload(
        key: String,
        fallbackFeature: String,
        fallbackOperation: String,
        fallbackMessage: String
    ) async throws -> ExportPayload {
        let context = await ErrorReportStore.shared.latest(for: key)
            ?? ErrorReportContext(
                capturedAt: Date(),
                feature: fallbackFeature,
                operation: fallbackOperation,
                userMessage: fallbackMessage,
                detailedLog: "No additional error details were captured.",
                llmInput: nil,
                llmOutput: nil,
                llmProvider: nil,
                llmModel: nil
            )
        let url = try writeReportFile(for: context)
        return ExportPayload(url: url)
    }

    private static func writeReportFile(for context: ErrorReportContext) throws -> URL {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: context.capturedAt)
        let content = """
        Vibe Food Error Report
        Generated At: \(timestamp)
        Feature: \(context.feature)
        Operation: \(context.operation)

        App
        - Version: \(appVersion)
        - Build: \(appBuild)
        - iOS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        - Device: \(UIDevice.current.model)

        User Facing Error
        \(context.userMessage)

        Detailed Error Log
        \(context.detailedLog)

        LLM Provider
        \(context.llmProvider?.isEmpty == false ? context.llmProvider! : "N/A")

        LLM Model
        \(context.llmModel?.isEmpty == false ? context.llmModel! : "N/A")

        LLM Input
        \(context.llmInput?.isEmpty == false ? context.llmInput! : "N/A")

        LLM Output
        \(context.llmOutput?.isEmpty == false ? context.llmOutput! : "N/A")
        """

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "vibe-food-error-report-\(formatter.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        guard let data = content.data(using: .utf8) else {
            throw NSError(
                domain: "ninja.roz.vibefood.error-report",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode report text as UTF-8."]
            )
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func detailedLog(for error: Error?) -> String {
        guard let error else {
            return "No additional error details were captured."
        }

        let nsError = error as NSError
        var lines: [String] = []
        lines.append("Error Type: \(String(reflecting: type(of: error)))")
        lines.append("NSError Domain: \(nsError.domain)")
        lines.append("NSError Code: \(nsError.code)")
        lines.append("Localized Description: \(error.localizedDescription)")
        lines.append("Debug Description: \(String(describing: error))")

        if let localized = error as? LocalizedError {
            if let errorDescription = localized.errorDescription {
                lines.append("LocalizedError Description: \(errorDescription)")
            }
            if let failureReason = localized.failureReason {
                lines.append("Failure Reason: \(failureReason)")
            }
            if let recoverySuggestion = localized.recoverySuggestion {
                lines.append("Recovery Suggestion: \(recoverySuggestion)")
            }
        }

        if !nsError.userInfo.isEmpty {
            lines.append("NSError UserInfo: \(nsError.userInfo)")
        }

        return lines.joined(separator: "\n")
    }

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
    }

    private static var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "Unknown"
    }
}
