import Foundation

struct IngredientImportPayload: Codable {
    struct MacrosPerPortion: Codable {
        let proteinG: Double
        let carbohydratesG: Double
        let totalFatG: Double

        enum CodingKeys: String, CodingKey {
            case proteinG = "protein_g"
            case carbohydratesG = "carbohydrates_g"
            case totalFatG = "total_fat_g"
        }
    }

    let productName: String
    let portionUnit: String
    let portionSize: Double
    let calories: Double
    let macrosPerPortion: MacrosPerPortion

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case portionUnit = "portion_unit"
        case portionSize = "portion_size"
        case calories
        case macrosPerPortion = "macros_per_portion"
    }
}

struct IngredientExportRow: Codable {
    let name: String
    let uuid: String
    let unit: String
}

struct IngredientImportService {
    func parse(data: Data) throws -> IngredientDraft {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(IngredientImportPayload.self, from: data)
        return IngredientDraft(
            name: payload.productName,
            unit: payload.portionUnit.lowercased(),
            portionSize: payload.portionSize,
            calories: payload.calories,
            protein: payload.macrosPerPortion.proteinG,
            carbs: payload.macrosPerPortion.carbohydratesG,
            fat: payload.macrosPerPortion.totalFatG
        )
    }
}
