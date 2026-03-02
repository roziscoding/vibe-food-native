import Foundation

struct MealImportPayload: Decodable {
    struct MatchedIngredient: Decodable {
        let ingredientId: UUID
        let amount: Double

        enum CodingKeys: String, CodingKey {
            case ingredientId = "ingredient_id"
            case amount
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
    }

    let matchedIngredients: [MatchedIngredient]
    let newIngredients: [NewIngredient]

    enum CodingKeys: String, CodingKey {
        case matchedIngredients = "matched_ingredients"
        case newIngredients = "new_ingredients"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchedIngredients = try container.decodeIfPresent([MatchedIngredient].self, forKey: .matchedIngredients) ?? []
        newIngredients = try container.decodeIfPresent([NewIngredient].self, forKey: .newIngredients) ?? []
    }
}

struct MealImportService {
    func parse(data: Data) throws -> MealImportPayload {
        let decoder = JSONDecoder()
        return try decoder.decode(MealImportPayload.self, from: data)
    }
}
