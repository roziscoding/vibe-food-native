import Foundation

enum AppTab: String, Hashable, CaseIterable {
    case dashboard
    case food
    case input
    case water
    case settings

    init?(commandValue: String) {
        switch commandValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dashboard", "overview", "home":
            self = .dashboard
        case "food", "meal", "meals":
            self = .food
        case "input", "log":
            self = .input
        case "water", "hydration":
            self = .water
        case "settings":
            self = .settings
        default:
            return nil
        }
    }
}

enum AppDayCommand {
    case today
    case previous
    case next
    case specific(Date)
}

enum AppCommand {
    case selectTab(AppTab)
    case setDay(AppDayCommand)
    case addWater(amountMl: Double, date: Date?)
    case addMeal(name: String, calories: Double, protein: Double, carbs: Double, fat: Double, date: Date?)
    case addIngredient(
        name: String,
        unit: String,
        portionSize: Double,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    )
}

enum AppCommandParseError: LocalizedError {
    case unsupportedScheme(String?)
    case missingCommand
    case unsupportedCommand(String)
    case invalidTab(String?)
    case invalidDay(String?)
    case invalidWaterAmount(String?)
    case missingValue(String)
    case invalidValue(field: String, value: String?)

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme '\(scheme ?? "nil")'. Use vibefood://..."
        case .missingCommand:
            return "Missing command path."
        case .unsupportedCommand(let command):
            return "Unsupported command '\(command)'."
        case .invalidTab(let value):
            return "Unsupported tab '\(value ?? "nil")'."
        case .invalidDay(let value):
            return "Unsupported day value '\(value ?? "nil")'. Use today, previous, next, or YYYY-MM-DD."
        case .invalidWaterAmount(let value):
            return "Invalid water amount '\(value ?? "nil")'. Use a positive number in ml."
        case .missingValue(let field):
            return "Missing required value '\(field)'."
        case .invalidValue(let field, let value):
            return "Invalid value '\(value ?? "nil")' for '\(field)'."
        }
    }
}

enum AppCommandParser {
    static let scheme = "vibefood"
    static let launchURLArgument = "--vf-url"
    static let launchURLEnvironment = "VF_URL_COMMAND"

    static func parse(url: URL) throws -> AppCommand {
        guard url.scheme?.lowercased() == scheme else {
            throw AppCommandParseError.unsupportedScheme(url.scheme)
        }

        let segments = normalizedSegments(from: url)
        guard let command = segments.first else {
            throw AppCommandParseError.missingCommand
        }

        let query = queryMap(from: url)
        switch command {
        case "tab":
            let rawTab = query["name"] ?? query["tab"] ?? segment(at: 1, in: segments)
            guard let rawTab, let tab = AppTab(commandValue: rawTab) else {
                throw AppCommandParseError.invalidTab(rawTab)
            }
            return .selectTab(tab)

        case "day":
            let rawDay = query["value"] ?? query["day"] ?? query["date"] ?? segment(at: 1, in: segments)
            guard let rawDay else {
                throw AppCommandParseError.invalidDay(nil)
            }
            return .setDay(try parseDay(rawDay))

        case "water":
            let action = (query["action"] ?? segment(at: 1, in: segments) ?? "").lowercased()
            guard action == "add" else {
                throw AppCommandParseError.unsupportedCommand("water/\(action)")
            }
            let rawAmount = query["ml"] ?? query["amount"] ?? segment(at: 2, in: segments)
            guard
                let rawAmount,
                let amount = Double(rawAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
                amount > 0
            else {
                throw AppCommandParseError.invalidWaterAmount(rawAmount)
            }
            let date: Date?
            if let rawDate = query["date"] {
                date = try parseDate(rawDate)
            } else {
                date = nil
            }
            return .addWater(amountMl: amount, date: date)

        case "meal", "meals":
            let action = (query["action"] ?? segment(at: 1, in: segments) ?? "").lowercased()
            guard action == "add" else {
                throw AppCommandParseError.unsupportedCommand("\(command)/\(action)")
            }
            let mealName = try requireNonEmptyString(
                query["name"] ?? segment(at: 2, in: segments),
                field: "name"
            )
            let calories = try parseNonNegativeDouble(
                query["kcal"] ?? query["calories"],
                defaultValue: 0,
                field: "kcal"
            )
            let protein = try parseNonNegativeDouble(query["protein"], defaultValue: 0, field: "protein")
            let carbs = try parseNonNegativeDouble(query["carbs"], defaultValue: 0, field: "carbs")
            let fat = try parseNonNegativeDouble(query["fat"], defaultValue: 0, field: "fat")
            let date: Date?
            if let rawDate = query["date"] {
                date = try parseDate(rawDate)
            } else {
                date = nil
            }

            return .addMeal(
                name: mealName,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                date: date
            )

        case "ingredient", "ingredients":
            let action = (query["action"] ?? segment(at: 1, in: segments) ?? "").lowercased()
            guard action == "add" else {
                throw AppCommandParseError.unsupportedCommand("\(command)/\(action)")
            }
            let ingredientName = try requireNonEmptyString(
                query["name"] ?? segment(at: 2, in: segments),
                field: "name"
            )
            let unit = try requireNonEmptyString(query["unit"], field: "unit")
            let portionSize = try parsePositiveDouble(
                query["portion"] ?? query["portion_size"] ?? query["portionSize"],
                defaultValue: 1,
                field: "portion"
            )
            let calories = try parseNonNegativeDouble(
                query["kcal"] ?? query["calories"],
                defaultValue: 0,
                field: "kcal"
            )
            let protein = try parseNonNegativeDouble(query["protein"], defaultValue: 0, field: "protein")
            let carbs = try parseNonNegativeDouble(query["carbs"], defaultValue: 0, field: "carbs")
            let fat = try parseNonNegativeDouble(query["fat"], defaultValue: 0, field: "fat")

            return .addIngredient(
                name: ingredientName,
                unit: unit,
                portionSize: portionSize,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            )

        default:
            throw AppCommandParseError.unsupportedCommand(command)
        }
    }

    private static func parseDay(_ raw: String) throws -> AppDayCommand {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "today":
            return .today
        case "previous", "prev", "yesterday":
            return .previous
        case "next", "tomorrow":
            return .next
        default:
            return .specific(try parseDate(raw))
        }
    }

    private static func parseDate(_ raw: String) throws -> Date {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = localDayFormatter.date(from: trimmed) else {
            throw AppCommandParseError.invalidDay(raw)
        }
        return date
    }

    private static func requireNonEmptyString(_ raw: String?, field: String) throws -> String {
        guard let raw else {
            throw AppCommandParseError.missingValue(field)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppCommandParseError.missingValue(field)
        }
        return trimmed
    }

    private static func parsePositiveDouble(
        _ raw: String?,
        defaultValue: Double,
        field: String
    ) throws -> Double {
        guard let raw else { return defaultValue }
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            throw AppCommandParseError.invalidValue(field: field, value: raw)
        }
        return value
    }

    private static func parseNonNegativeDouble(
        _ raw: String?,
        defaultValue: Double,
        field: String
    ) throws -> Double {
        guard let raw else { return defaultValue }
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
            throw AppCommandParseError.invalidValue(field: field, value: raw)
        }
        return value
    }

    private static func normalizedSegments(from url: URL) -> [String] {
        var segments: [String] = []
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            segments.append(host.lowercased())
        }

        let pathSegments = url.path
            .split(separator: "/")
            .map { String($0).lowercased() }
        segments.append(contentsOf: pathSegments)

        if segments.first == "command" {
            segments.removeFirst()
        }
        return segments
    }

    private static func segment(at index: Int, in values: [String]) -> String? {
        guard values.indices.contains(index) else { return nil }
        return values[index]
    }

    private static func queryMap(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }

        var map: [String: String] = [:]
        for item in queryItems {
            guard let value = item.value else { continue }
            map[item.name.lowercased()] = value
        }
        return map
    }

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(arguments: [String], environment: [String: String]) throws -> AppCommand? {
        if let rawURL = environment[launchURLEnvironment], !rawURL.isEmpty {
            guard let url = URL(string: rawURL) else {
                throw AppCommandParseError.missingCommand
            }
            return try parse(url: url)
        }

        guard let index = arguments.firstIndex(of: launchURLArgument) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            throw AppCommandParseError.missingCommand
        }
        guard let url = URL(string: arguments[valueIndex]) else {
            throw AppCommandParseError.missingCommand
        }
        return try parse(url: url)
    }
}
