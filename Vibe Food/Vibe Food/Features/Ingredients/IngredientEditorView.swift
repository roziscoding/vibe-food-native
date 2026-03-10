import SwiftUI

struct IngredientEditorView: View {
    @Binding var draft: IngredientDraft
    var errorMessage: String?
    var fieldErrors: [String: String]
    var onSave: () -> Void
    var onCancel: () -> Void
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                Form {
                    Section("Basics") {
                        TextField("Name", text: $draft.name)

                        if let nameError = fieldErrors["name"] {
                            Text(nameError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }

                        HStack {
                            Text("Unit")
                            Spacer()
                            TextField("", text: $draft.unit)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .frame(maxWidth: 140)
                        }

                        HStack {
                            Text("Portion Size")
                            Spacer()
                            TextField("", value: $draft.portionSize, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                        }
                    }

                    if let errorMessage {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.footnote)

                                Button("Report") {
                                    Task {
                                        errorReportPayload = try? await ErrorReportService.makePayload(
                                            key: ErrorReportKey.ingredientsAlert,
                                            fallbackFeature: "Ingredients",
                                            fallbackOperation: "Save ingredient draft",
                                            fallbackMessage: errorMessage
                                        )
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGlass.accent)
                            }
                        }
                    }

                    Section("Macros Per Portion") {
                        if let macroError = fieldErrors["macros"] {
                            Text(macroError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }

                        HStack {
                            Text("Calories")
                            Spacer()
                            TextField("", value: $draft.calories, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                        }

                        HStack {
                            Text("Protein")
                            Spacer()
                            TextField("", value: $draft.protein, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                        }

                        HStack {
                            Text("Carbs")
                            Spacer()
                            TextField("", value: $draft.carbs, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                        }

                        HStack {
                            Text("Fat")
                            Spacer()
                            TextField("", value: $draft.fat, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                        }
                    }

                    Section("Per Unit Preview") {
                        let perUnit = perUnitPreview()
                        HStack {
                            Text("Calories / \(draft.unit)")
                            Spacer()
                            Text(perUnit.calories)
                        }
                        HStack {
                            Text("Protein / \(draft.unit)")
                            Spacer()
                            Text(perUnit.protein)
                        }
                        HStack {
                            Text("Carbs / \(draft.unit)")
                            Spacer()
                            Text(perUnit.carbs)
                        }
                        HStack {
                            Text("Fat / \(draft.unit)")
                            Spacer()
                            Text(perUnit.fat)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Ingredient")
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                }
            }
            .sheet(item: $errorReportPayload) { payload in
                ShareSheet(items: [payload.url])
            }
        }
    }

    private func perUnitPreview() -> (calories: String, protein: String, carbs: String, fat: String) {
        guard draft.portionSize > 0,
              [draft.calories, draft.protein, draft.carbs, draft.fat].allSatisfy({ $0.isFinite && $0 >= 0 })
        else {
            return ("-", "-", "-", "-")
        }

        let calories = draft.calories / draft.portionSize
        let protein = draft.protein / draft.portionSize
        let carbs = draft.carbs / draft.portionSize
        let fat = draft.fat / draft.portionSize

        return (
            format(calories),
            format(protein),
            format(carbs),
            format(fat)
        )
    }

    private func format(_ value: Double) -> String {
        AppFormatters.number.string(from: NSNumber(value: value)) ?? "0"
    }
}
