import SwiftUI

struct MealEditorView: View {
    @Bindable var store: MealsStore
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                if let draft = store.draft {
                    Form {
                    if let errorMessage = store.draftError {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.footnote)

                                Button("Report") {
                                    Task {
                                        errorReportPayload = try? await ErrorReportService.makePayload(
                                            key: ErrorReportKey.mealsDraft,
                                            fallbackFeature: "Meals",
                                            fallbackOperation: "Save meal draft",
                                            fallbackMessage: errorMessage
                                        )
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGlass.accent)
                            }
                        }
                    }

                    Section("Basics") {
                        TextField("Meal Name", text: binding(for: draft).name)

                        DatePicker("Date & Time", selection: binding(for: draft).consumedAt, displayedComponents: [.date, .hourAndMinute])

                        if let nameError = store.fieldErrors["name"] {
                            Text(nameError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }

                    if !binding(for: draft).importIssues.wrappedValue.isEmpty {
                        Section("Import Issues") {
                            ForEach(binding(for: draft).importIssues.wrappedValue) { issue in
                                HStack {
                                    Text(issue.message)
                                        .foregroundStyle(.orange)
                                        .font(.footnote)
                                    Spacer()
                                    Picker("Ingredient", selection: ingredientLineBinding(for: issue.lineId).ingredientId) {
                                        Text("Select").tag(UUID?.none)
                                        ForEach(store.ingredients) { ingredient in
                                            Text(ingredient.name).tag(Optional(ingredient.id))
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }
                        }
                    }

                    if !binding(for: draft).stagedIngredients.wrappedValue.isEmpty {
                        Section("New Ingredients") {
                            ForEach(binding(for: draft).stagedIngredients.wrappedValue.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Name", text: stagedBinding(for: index).name)
                                    HStack {
                                        Text("Unit")
                                        Spacer()
                                        TextField("", text: stagedBinding(for: index).unit)
                                            .multilineTextAlignment(.trailing)
                                            .textInputAutocapitalization(.never)
                                            .disableAutocorrection(true)
                                            .frame(maxWidth: 140)
                                    }
                                    HStack {
                                        Text("Portion Size")
                                        Spacer()
                                        TextField("", value: stagedBinding(for: index).portionSize, format: .number)
                                            .multilineTextAlignment(.trailing)
                                            .keyboardType(.decimalPad)
                                            .frame(maxWidth: 140)
                                    }
                                    HStack {
                                        Text("Calories")
                                        Spacer()
                                        TextField("", value: stagedBinding(for: index).calories, format: AppFormatters.integerInputFormat)
                                            .multilineTextAlignment(.trailing)
                                            .keyboardType(.numberPad)
                                            .frame(maxWidth: 140)
                                    }
                                    HStack {
                                        Text("Protein")
                                        Spacer()
                                        TextField("", value: stagedBinding(for: index).protein, format: AppFormatters.integerInputFormat)
                                            .multilineTextAlignment(.trailing)
                                            .keyboardType(.numberPad)
                                            .frame(maxWidth: 140)
                                    }
                                    HStack {
                                        Text("Carbs")
                                        Spacer()
                                        TextField("", value: stagedBinding(for: index).carbs, format: AppFormatters.integerInputFormat)
                                            .multilineTextAlignment(.trailing)
                                            .keyboardType(.numberPad)
                                            .frame(maxWidth: 140)
                                    }
                                    HStack {
                                        Text("Fat")
                                        Spacer()
                                        TextField("", value: stagedBinding(for: index).fat, format: AppFormatters.integerInputFormat)
                                            .multilineTextAlignment(.trailing)
                                            .keyboardType(.numberPad)
                                            .frame(maxWidth: 140)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section("Entry Mode") {
                        Picker("Mode", selection: $store.entryMode) {
                            Text("Manual").tag(MealEntryMode.manual)
                            Text("Ingredients").tag(MealEntryMode.ingredients)
                        }
                        .pickerStyle(.segmented)
                    }

                        if store.entryMode == .manual {
                            manualSection(binding: binding(for: draft))
                        } else {
                            ingredientsSection(binding: binding(for: draft))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .navigationTitle("Meal")
                    .keyboardDoneToolbar()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { store.cancelEdit() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { store.saveDraft() }
                        }
                    }
                    .sheet(item: $errorReportPayload) { payload in
                        ShareSheet(items: [payload.url])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func manualSection(binding: Binding<MealDraft>) -> some View {
        Section("Macros") {
            macroRow(title: "Calories", unit: "kcal", value: binding.calories)
            macroRow(title: "Protein", unit: "g", value: binding.protein)
            macroRow(title: "Carbs", unit: "g", value: binding.carbs)
            macroRow(title: "Fat", unit: "g", value: binding.fat)
        }
    }

    @ViewBuilder
    private func ingredientsSection(binding: Binding<MealDraft>) -> some View {
        Group {
            Section("Ingredients") {
                ForEach(binding.ingredientLines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Ingredient", selection: Binding(
                            get: { line.ingredientId },
                            set: { newValue in
                                line.ingredientId = newValue
                                store.setIngredient(lineId: line.id, ingredientId: newValue)
                            }
                        )) {
                            Text("Select ingredient").tag(UUID?.none)
                            ForEach(store.ingredients) { ingredient in
                                Text(ingredient.name).tag(Optional(ingredient.id))
                            }
                        }

                        Picker("Amount In", selection: $line.amountInputMode) {
                            Text("Portions").tag(MealIngredientAmountInputMode.portions)
                            Text(line.unit.isEmpty ? "Unit" : line.unit).tag(MealIngredientAmountInputMode.unit)
                        }
                        .pickerStyle(.segmented)
                        .disabled(line.ingredientId == nil)

                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("", value: amountInputBinding(for: $line), format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                            Text(amountInputUnitLabel(for: line))
                                .foregroundStyle(.secondary)
                        }

                        if let portionHint = portionHint(for: line) {
                            Text(portionHint)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }

                        if line.ingredientId == nil {
                            Text("Select an ingredient for this line.")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                    }
                }

                if let ingredientsError = store.fieldErrors["ingredients"] {
                    Text(ingredientsError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button("Add Ingredient") {
                    store.addIngredientLine()
                }
            }

            Section("Totals") {
                let totals = storeTotals(from: binding.wrappedValue.ingredientLines)
                macroRow(title: "Calories", unit: "kcal", value: .constant(totals.calories))
                    .disabled(true)
                macroRow(title: "Protein", unit: "g", value: .constant(totals.protein))
                    .disabled(true)
                macroRow(title: "Carbs", unit: "g", value: .constant(totals.carbs))
                    .disabled(true)
                macroRow(title: "Fat", unit: "g", value: .constant(totals.fat))
                    .disabled(true)
            }
        }
    }

    private func macroRow(title: String, unit: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: value, format: AppFormatters.integerInputFormat)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(maxWidth: 120)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for draft: MealDraft) -> Binding<MealDraft> {
        Binding(
            get: { store.draft ?? draft },
            set: { store.draft = $0 }
        )
    }

    private func ingredientLineBinding(for lineId: UUID) -> Binding<MealDraftIngredientLine> {
        Binding(
            get: {
                store.draft?.ingredientLines.first(where: { $0.id == lineId })
                    ?? MealDraftIngredientLine(id: lineId, ingredientId: nil, name: "", amount: 0, unit: "")
            },
            set: { newValue in
                guard var draft = store.draft,
                      let index = draft.ingredientLines.firstIndex(where: { $0.id == lineId })
                else { return }
                draft.ingredientLines[index] = newValue
                store.setIngredient(lineId: lineId, ingredientId: newValue.ingredientId)
                store.draft = draft
            }
        )
    }

    private func stagedBinding(for index: Int) -> Binding<IngredientDraft> {
        Binding(
            get: { store.draft?.stagedIngredients[index] ?? IngredientDraft(name: "", unit: "", portionSize: 1, calories: 0, protein: 0, carbs: 0, fat: 0) },
            set: { newValue in
                guard var draft = store.draft else { return }
                draft.stagedIngredients[index] = newValue
                store.draft = draft
            }
        )
    }

    private func amountInputBinding(for line: Binding<MealDraftIngredientLine>) -> Binding<Double> {
        Binding(
            get: {
                let lineValue = line.wrappedValue
                guard lineValue.amountInputMode == .portions,
                      let portionSize = portionSize(for: lineValue),
                      portionSize > 0
                else {
                    return lineValue.amount
                }
                return lineValue.amount / portionSize
            },
            set: { newValue in
                var updatedLine = line.wrappedValue
                guard updatedLine.amountInputMode == .portions,
                      let portionSize = portionSize(for: updatedLine),
                      portionSize > 0
                else {
                    updatedLine.amount = newValue
                    line.wrappedValue = updatedLine
                    return
                }

                updatedLine.amount = newValue * portionSize
                line.wrappedValue = updatedLine
            }
        )
    }

    private func amountInputUnitLabel(for line: MealDraftIngredientLine) -> String {
        switch line.amountInputMode {
        case .portions:
            return "portions"
        case .unit:
            return line.unit.isEmpty ? "unit" : line.unit
        }
    }

    private func portionHint(for line: MealDraftIngredientLine) -> String? {
        guard line.amountInputMode == .portions,
              let portionSize = portionSize(for: line),
              portionSize > 0
        else {
            return nil
        }

        let unitLabel = line.unit.isEmpty ? "unit" : line.unit
        return "1 portion = \(portionSize.formatted(.number)) \(unitLabel)"
    }

    private func portionSize(for line: MealDraftIngredientLine) -> Double? {
        guard let ingredientId = line.ingredientId,
              let ingredient = store.ingredients.first(where: { $0.id == ingredientId })
        else {
            return nil
        }
        return ingredient.portionSize
    }

    private func storeTotals(from lines: [MealDraftIngredientLine]) -> MacroBreakdown {
        let validLines = lines.filter { $0.ingredientId != nil && $0.amount > 0 }
        return storeTotals(for: validLines)
    }

    private func storeTotals(for lines: [MealDraftIngredientLine]) -> MacroBreakdown {
        var totals = MacroBreakdown(calories: 0, protein: 0, carbs: 0, fat: 0)
        for line in lines {
            guard let ingredientId = line.ingredientId,
                  let ingredient = store.ingredients.first(where: { $0.id == ingredientId })
            else { continue }
            totals.calories += ingredient.caloriesPerUnit * line.amount
            totals.protein += ingredient.proteinPerUnit * line.amount
            totals.carbs += ingredient.carbsPerUnit * line.amount
            totals.fat += ingredient.fatPerUnit * line.amount
        }
        return NutritionRounding.round(totals)
    }
}
