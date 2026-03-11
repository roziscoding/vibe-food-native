import Foundation

enum AppFormatters {
    static let integerInputFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0))

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func integerText(_ value: Double) -> String {
        integer.string(from: NSNumber(value: value)) ?? "0"
    }

    static func calorieText(_ value: Double) -> String {
        integerText(NutritionRounding.roundCalories(value))
    }

    static func macroText(_ value: Double) -> String {
        integerText(NutritionRounding.roundMacro(value))
    }
}
